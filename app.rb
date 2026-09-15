require_relative 'config/environment'

require 'uri'
require 'sinatra/activerecord'
require 'phlex-sinatra'
require 'phlex'

# Models, services and views are loaded by config.ru through Rack::Unreloader so
# they can hot-reload in development; don't plain-require them here or the
# reloader loses track of them.

class App < Sinatra::Base
  helpers Phlex::Sinatra
  register Sinatra::ActiveRecordExtension

  # Connect using the same ENV-aware config the bot and console use, rather than
  # letting the extension read config/database.yml on its own.
  set :database, Abid.database_config

  # The board's edit/delete forms rely on _method; Sinatra::Base leaves this off
  # by default (unlike a classic Sinatra app).
  enable :method_override

  set :sessions,
      httponly: true,
      secure: production?,
      same_site: :lax,
      expire_after: 60 * 60 * 24 * 14
  set :session_secret, Abid.session_secret

  before do
    # Lets Layout highlight the active nav entry without every page view
    # threading the path through its constructor.
    Abid.current_path = request.path_info
    ensure_logged_in
  end

  get '/' do
    upcoming = Event.active.upcoming.includes(:location, :series, rides: :user).chronological.limit(6).to_a
    next_event = upcoming.first

    phlex Home.new(
      next_event: next_event,
      board: next_event && RideBoard.new(next_event),
      upcoming: upcoming.drop(1),
      needs_setup: User.missing_details.limit(50).to_a,
      leader: leader?
    )
  end

  get '/login' do
    phlex Login.new
  end

  post '/login' do
    # Case-insensitive: Discord usernames are lowercase now, but rows synced from
    # older accounts can be mixed case.
    user = User.where('lower(username) = ?', params[:username].to_s.strip.downcase).first

    # user may be nil, and authenticate returns false on a bad password, so this
    # has to be a safe-navigation check rather than `user.authenticate(...)`.
    if user&.authenticate(params[:password].to_s)
      session[:user_id] = user.id
      redirect to('/')
    else
      status 401
      phlex Login.new(error: 'Incorrect username or password.')
    end
  end

  get '/logout' do
    session.clear
    redirect to('/login')
  end

  # --- events ---------------------------------------------------------------

  get '/events' do
    filter = %w[upcoming past all].include?(params[:when]) ? params[:when] : 'upcoming'
    phlex EventsIndex.new(events: events_for(filter), filter: filter, leader: leader?)
  end

  # Must precede '/events/:id', which would otherwise match "new".
  get '/events/new' do
    require_leader!
    phlex EventForm.new(event: Event.new, **form_collections, leader: leader?)
  end

  post '/events' do
    require_leader!
    event = Event.new(event_params)
    if event.save
      redirect to("/events/#{event.id}")
    else
      status 422
      phlex EventForm.new(event: event, **form_collections, leader: leader?,
                          error: event.errors.full_messages.to_sentence)
    end
  end

  get '/events/:id.csv' do
    event = find_event(params[:id]) or halt 404, 'No such event'
    content_type 'text/csv'
    attachment "rides-#{event.start_time&.strftime('%Y-%m-%d') || event.id}.csv"
    RideBoardCsv.new(RideBoard.new(event)).to_csv
  end

  get '/events/:id' do
    event = find_event(params[:id]) or halt 404, 'No such event'
    phlex EventShow.new(event: event, board: RideBoard.new(event), leader: leader?)
  end

  get '/events/:id/edit' do
    require_leader!
    event = find_event(params[:id]) or halt 404, 'No such event'
    phlex EventForm.new(event: event, **form_collections, leader: leader?)
  end

  patch '/events/:id' do
    require_leader!
    event = find_event(params[:id]) or halt 404, 'No such event'
    if event.update(event_params)
      redirect to("/events/#{event.id}")
    else
      status 422
      phlex EventForm.new(event: event, **form_collections, leader: leader?,
                          error: event.errors.full_messages.to_sentence)
    end
  end

  # Disable, never destroy — a past occurrence is the only record of who rode
  # with whom.
  post '/events/:id/disable' do
    require_leader!
    event = find_event(params[:id]) or halt 404, 'No such event'
    event.update(disabled: !event.disabled)
    redirect to("/events/#{event.id}")
  end

  # --- members --------------------------------------------------------------

  get '/users' do
    filter = %w[all drivers leaders missing].include?(params[:filter]) ? params[:filter] : 'all'
    users = users_for(filter, params[:q])

    phlex UsersIndex.new(
      users: users,
      load: DriverLoad.new,
      filter: filter,
      query: params[:q],
      counts: user_counts,
      leader: leader?
    )
  end

  get '/users/:id' do
    user = User.find_by(id: params[:id]) or halt 404, 'No such member'
    phlex user_page(user)
  end

  patch '/users/:id' do
    require_leader!
    user = User.find_by(id: params[:id]) or halt 404, 'No such member'

    if user.update(user_params)
      redirect to("/users/#{user.id}")
    else
      status 422
      phlex user_page(user, error: user.errors.full_messages.to_sentence)
    end
  end

  # --- locations ------------------------------------------------------------

  # Read-only. The list is real geography maintained in db/locations.rb, not
  # per-event data, so there is deliberately no editing UI.
  get '/locations' do
    locations = Location.order(:name).to_a
    phlex LocationsIndex.new(
      by_zone: locations.select(&:zone).group_by(&:zone),
      unzoned: locations.reject(&:zone),
      usage: location_usage,
      leader: leader?
    )
  end

  # --- recurring series -----------------------------------------------------

  get '/series' do
    phlex series_page
  end

  # Academic breaks live on the series page because that is the only thing they
  # affect. Shared across every series — the calendar belongs to the university.
  post '/breaks' do
    require_leader!
    academic_break = AcademicBreak.new(permitted(%w[name starts_on ends_on]))

    if academic_break.save
      # Occurrences generated before the break existed are now wrong; switch
      # off the upcoming ones rather than deleting anyone's roster.
      academic_break.disable_future_occurrences!
      redirect to('/series')
    else
      status 422
      phlex series_page(error: academic_break.errors.full_messages.to_sentence)
    end
  end

  delete '/breaks/:id' do
    require_leader!
    AcademicBreak.find_by(id: params[:id])&.destroy
    EventGenerator.call
    redirect to('/series')
  end

  get '/series/new' do
    require_leader!
    phlex SeriesForm.new(series: EventSeries.new(interval_weeks: 1, horizon_weeks: 3,
                                                 message_lead_hours: 24, collect_lead_hours: 2),
                         **form_collections, leader: leader?)
  end

  post '/series' do
    require_leader!
    series = EventSeries.new(series_params)
    if series.save
      EventGenerator.call(only: series)
      redirect to("/series/#{series.id}")
    else
      status 422
      phlex SeriesForm.new(series: series, **form_collections, leader: leader?,
                           error: series.errors.full_messages.to_sentence)
    end
  end

  get '/series/:id' do
    series = EventSeries.find_by(id: params[:id]) or halt 404, 'No such series'
    phlex SeriesShow.new(
      series: series,
      upcoming: series.events.upcoming.chronological.to_a,
      past: series.events.past.order(start_time: :desc).limit(25).to_a,
      leader: leader?
    )
  end

  get '/series/:id/edit' do
    require_leader!
    series = EventSeries.find_by(id: params[:id]) or halt 404, 'No such series'
    phlex SeriesForm.new(series: series, **form_collections, leader: leader?)
  end

  patch '/series/:id' do
    require_leader!
    series = EventSeries.find_by(id: params[:id]) or halt 404, 'No such series'
    if series.update(series_params)
      EventGenerator.call(only: series) unless series.disabled
      redirect to("/series/#{series.id}")
    else
      status 422
      phlex SeriesForm.new(series: series, **form_collections, leader: leader?,
                           error: series.errors.full_messages.to_sentence)
    end
  end

  post '/series/:id/generate' do
    require_leader!
    series = EventSeries.find_by(id: params[:id]) or halt 404, 'No such series'
    EventGenerator.call(only: series)
    redirect to("/series/#{series.id}")
  end

  # --- sign-up posts --------------------------------------------------------

  get '/signups' do
    posts = SignupPost.includes(:channel, :options).recent.limit(50)
    phlex SignupsIndex.new(posts: posts, channels: Channel.order(:name).to_a, leader: leader?)
  end

  post '/signups' do
    require_leader!
    post = SignupPost.new(
      channel_id: params[:channel_id],
      service_date: params[:service_date].presence,
      created_by: current_user
    )
    halt 422, post.errors.full_messages.to_sentence unless post.save
    redirect to("/signups/#{post.id}")
  end

  get '/signups/:id' do
    phlex signup_page(find_signup(params[:id]))
  end

  patch '/signups/:id' do
    require_leader!
    post = find_signup(params[:id])
    halt 409, 'This post has already been sent.' unless post.editable?

    attrs = permitted(%w[channel_id service_date post_at intro outro])
    if post.update(attrs)
      redirect to("/signups/#{post.id}")
    else
      status 422
      phlex signup_page(post, error: post.errors.full_messages.to_sentence)
    end
  end

  delete '/signups/:id' do
    require_leader!
    post = find_signup(params[:id])
    halt 409, 'This post has already been sent.' unless post.editable?

    post.destroy
    redirect to('/signups')
  end

  post '/signups/:id/options' do
    require_leader!
    post = find_signup(params[:id])
    halt 409, 'This post has already been sent.' unless post.editable?

    attrs = Signup::EmojiKey.parse(params[:emoji])
    halt 422, "Could not read #{params[:emoji].inspect} as an emoji." if attrs.nil?

    option = post.options.build(
      attrs.merge(
        event_id: params[:event_id].presence,
        label: params[:label].presence,
        position: post.options.size
      )
    )
    halt 422, option.errors.full_messages.to_sentence.presence || 'Could not add that option.' unless option.save
    redirect to("/signups/#{post.id}")
  end

  patch '/signups/:id/options/:option_id' do
    require_leader!
    post = find_signup(params[:id])
    halt 409, 'This post has already been sent.' unless post.editable?

    option = post.options.find(params[:option_id])
    option.event_id = params[:event_id].presence
    option.label = params[:label].presence
    if option.save
      redirect to("/signups/#{post.id}")
    else
      status 422
      phlex signup_page(post, error: option.errors.full_messages.to_sentence)
    end
  end

  delete '/signups/:id/options/:option_id' do
    require_leader!
    post = find_signup(params[:id])
    halt 409, 'This post has already been sent.' unless post.editable?

    post.options.find(params[:option_id]).destroy
    redirect to("/signups/#{post.id}")
  end

  # Hand the post to the bot. It polls SignupPost.due every 30 seconds.
  post '/signups/:id/schedule' do
    require_leader!
    post = find_signup(params[:id])
    halt 422, 'Every option needs a ride, and the post needs a send time.' unless post.schedule!
    redirect to("/signups/#{post.id}")
  end

  post '/signups/:id/unschedule' do
    require_leader!
    find_signup(params[:id]).unschedule!
    redirect to("/signups/#{params[:id]}")
  end

  post '/signups/:id/close' do
    require_leader!
    find_signup(params[:id]).close!
    redirect to("/signups/#{params[:id]}")
  end

  post '/signups/:id/reopen' do
    require_leader!
    find_signup(params[:id]).reopen!
    redirect to("/signups/#{params[:id]}")
  end

  # Ask the bot for a sweep. It polls for this every 15 seconds.
  post '/signups/:id/resync' do
    require_leader!
    find_signup(params[:id]).update!(reconcile_requested_at: Time.zone.now)
    redirect to("/signups/#{params[:id]}")
  end

  # --- ride board ----------------------------------------------------------

  # The board for one occurrence. Without an id we pick the next upcoming one so
  # "/board" is a usable bookmark on a Sunday morning.
  get '/board' do
    event = find_event(params[:event_id]) || default_event
    halt 404, 'No upcoming events. Create one in Discord with /event create.' if event.nil?

    page = board_page(event)
    # The live filter re-fetches this route, so serve it the swappable fragment.
    (request.xhr? || params[:fragment] == '1') ? phlex(page.fragment) : phlex(page)
  end

  # Every mutation below re-renders the board and returns it as a fragment, so
  # the page swaps one div instead of reloading. Without JS the same routes still
  # work and just redirect back to the board.
  post '/board/:event_id/assign' do
    with_board do |event, history|
      ride = event.rides.riders.find(params[:ride_id])
      target = params[:driver_ride_id].presence && event.rides.drivers.find(params[:driver_ride_id])

      history.record([ride])
      ride.update!(
        driver_ride_id: target&.id,
        status: target ? 'assigned' : 'requested'
      )
    end
  end

  post '/board/:event_id/autofill' do
    with_board do |event, history|
      history.record(event.rides.unassigned.to_a)
      AutoFiller.new(event, strategy: params[:strategy].to_s).call
    end
  end

  post '/board/:event_id/undo' do
    with_board { |_event, history| history.undo! }
  end

  # Rider "not coming" and driver "not driving today" are the same toggle.
  post '/board/:event_id/toggle-out' do
    with_board do |event, history|
      ride = event.rides.find(params[:ride_id])
      history.record([ride])

      if ride.out?
        ride.update!(status: ride.driver_ride_id ? 'assigned' : 'requested')
      else
        ride.update!(status: ride.driver? ? 'cancelled' : 'no_show', driver_ride_id: nil)
      end
    end
  end

  patch '/board/:event_id/rides/:ride_id' do
    with_board do |event, _history|
      ride = event.rides.find(params[:ride_id])
      RideDetails.new(ride).apply(params)
    end
  end

  delete '/board/:event_id/rides/:ride_id' do
    with_board do |event, _history|
      event.rides.find(params[:ride_id]).destroy
    end
  end

  post '/board/:event_id/rides' do
    with_board do |event, _history|
      RideDetails.create_for(event, params)
    end
  end

  post '/board/:event_id/clashes' do
    with_board do |event, _history|
      a = event.rides.find(params[:ride_id]).user_id
      b = event.rides.find(params[:other_ride_id]).user_id
      Clash.add(a, b)
    end
  end

  delete '/board/:event_id/clashes' do
    with_board do |event, _history|
      a = event.rides.find(params[:ride_id]).user_id
      b = event.rides.find(params[:other_ride_id]).user_id
      Clash.remove(a, b)
    end
  end

  # Queue DMs to drivers. The roster is snapshotted here, in this request, so
  # what goes out is what the coordinator was looking at — the bot only renders
  # and delivers.
  post '/board/:event_id/dispatch' do
    require_leader!
    event = find_event(params[:event_id]) or halt 404, 'No such event'

    dispatch = DispatchPlanner.new(
      RideBoard.new(event),
      requested_by: current_user,
      scope: params[:scope].to_s
    ).call

    halt 422, 'Nobody to send to.' if dispatch.nil?
    render_board(event)
  end

  get '/events/:event_id/dispatches' do
    event = find_event(params[:event_id]) or halt 404, 'No such event'
    dispatches = event.dispatches.includes(:requested_by, messages: :user).recent.to_a
    phlex DispatchLog.new(event: event, dispatches: dispatches, leader: leader?)
  end

  get '/board/:event_id.csv' do
    event = find_event(params[:event_id]) or halt 404
    content_type 'text/csv'
    attachment "rides-#{event.start_time&.strftime('%Y-%m-%d') || event.id}.csv"
    RideBoardCsv.new(RideBoard.new(event)).to_csv
  end

  private

  PUBLIC_PATHS = ['/login'].freeze

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = session[:user_id] && User.find_by(id: session[:user_id])
  end

  def leader?
    !!current_user&.leader
  end

  def ensure_logged_in
    return if PUBLIC_PATHS.include?(request.path_info)

    # A stale session cookie pointing at a deleted user (someone left the server)
    # should log out cleanly rather than 500 further down the request.
    return if current_user

    session.clear
    redirect to('/login')
  end

  # Guard for anything that edits data. The bot checks `leader` per command; the
  # web side previously checked only "is logged in".
  def require_leader!
    halt 403, 'Leaders only' unless leader?
  end

  def find_event(id)
    return nil if id.blank?
    Event.find_by(id: id)
  end

  # Rides are preloaded because EventTable counts riders and drivers per row.
  def events_for(filter)
    scope = Event.includes(:location, :series, rides: :user)
    case filter
    when 'past' then scope.past.order(start_time: :desc).limit(200)
    when 'all' then scope.order(start_time: :desc).limit(200)
    else scope.upcoming.chronological
    end.to_a
  end

  def series_page(error: nil)
    series = EventSeries.order(:name).to_a
    SeriesIndex.new(
      series: series,
      upcoming: upcoming_by_series(series),
      breaks: AcademicBreak.chronological.to_a,
      leader: leader?,
      error: error
    )
  end

  def upcoming_by_series(series)
    return {} if series.empty?

    Event.upcoming.chronological
         .where(series_id: series.map(&:id))
         .group_by(&:series_id)
         .transform_values { |events| events.first(4) }
  end

  def find_signup(id)
    SignupPost.includes(:channel, options: :event).find_by(id: id) or halt 404, 'No such sign-up post'
  end

  def signup_page(post, error: nil)
    SignupShow.new(
      post: post,
      candidates: signup_candidates(post),
      channels: Channel.order(:name).to_a,
      leader: leader?,
      error: error
    )
  end

  # Occurrences a sign-up post could plausibly be about: anything still upcoming,
  # nearest first. Deliberately not filtered to the post's own date — a
  # coordinator often posts on Thursday for Sunday.
  def signup_candidates(post)
    from = post.service_date ? post.service_date.beginning_of_day : Time.zone.now
    Event.active
         .where('start_time >= ?', [from, Time.zone.now - 1.day].min)
         .chronological
         .limit(40)
         .to_a
  end

  def users_for(filter, query)
    scope = User.includes(:location).by_name
    scope = scope.search(query) if query.present?

    case filter
    when 'drivers' then scope.drivers
    when 'leaders' then scope.leaders
    when 'missing' then scope.missing_details
    else scope
    end.to_a
  end

  # Counts ignore the search box: the tabs should say how many drivers exist,
  # not how many match what is currently typed.
  def user_counts
    {
      'all' => User.count,
      'drivers' => User.drivers.count,
      'leaders' => User.leaders.count,
      'missing' => User.missing_details.count
    }
  end

  USER_FIELDS = %w[name phone location_id capacity grad_year].freeze

  def user_params
    permitted(USER_FIELDS).merge('leader' => params[:leader] == '1')
  end

  def user_page(user, error: nil)
    UserShow.new(
      user: user,
      locations: Location.order(:name).to_a,
      load: DriverLoad.new,
      history: user.rides.includes(:event).joins(:event)
                   .where.not(events: { start_time: nil })
                   .order('events.start_time DESC').limit(12).to_a,
      leader: leader?,
      error: error
    )
  end

  # Two grouped counts rather than N per-row queries.
  def location_usage
    users = User.where.not(location_id: nil).group(:location_id).count
    rides = Ride.where.not(pickup_location_id: nil).group(:pickup_location_id).count

    (users.keys | rides.keys).to_h do |id|
      [id, { users: users[id].to_i, rides: rides[id].to_i }]
    end
  end

  def form_collections
    { channels: Channel.order(:name).to_a, locations: Location.order(:name).to_a }
  end

  EVENT_FIELDS = %w[name section start_time end_time message_rides_at collect_rides_at
                    channel_id location_id message].freeze

  SERIES_FIELDS = %w[name section weekday interval_weeks start_time_of_day end_time_of_day
                     message_lead_hours collect_lead_hours channel_id location_id message
                     starts_on ends_on horizon_weeks].freeze

  def event_params
    permitted(EVENT_FIELDS).merge('disabled' => params[:disabled] == '1')
  end

  def series_params
    permitted(SERIES_FIELDS).merge('disabled' => params[:disabled] == '1')
  end

  # Blank strings from an HTML form must become NULL, not "", or a blank
  # datetime-local field would fail to cast and a blank select would write an
  # empty foreign key.
  def permitted(fields)
    params.slice(*fields).to_h.transform_values { |value| value.is_a?(String) ? value.presence : value }
  end

  def default_event
    Event.active.upcoming.chronological.first || Event.active.chronological.last
  end

  def board_page(event)
    Board.new(
      board: RideBoard.new(
        event,
        query: params[:q],
        selected_ride_id: params[:sel],
        focus_ride_id: params[:focus]
      ),
      can_undo: AssignmentHistory.new(session, event).any?,
      leader: leader?,
      tab: params[:tab] == 'roster' ? :roster : :details,
      strategy: params[:strategy].presence || 'closest'
    )
  end

  # Shared wrapper for board mutations: authorise, run the change, then hand back
  # a freshly rendered board.
  def with_board
    require_leader!
    event = find_event(params[:event_id]) or halt 404, 'No such event'
    history = AssignmentHistory.new(session, event)

    yield event, history

    render_board(event)
  rescue ActiveRecord::RecordNotFound
    halt 404, 'No such ride'
  rescue ActiveRecord::RecordInvalid => e
    halt 422, e.record.errors.full_messages.to_sentence
  end

  def render_board(event)
    if request.xhr? || params[:fragment] == '1'
      phlex board_page(event).fragment
    else
      redirect back_to_board(event)
    end
  end

  def back_to_board(event)
    query = { event_id: event.id, q: params[:q], tab: params[:tab], focus: params[:focus] }.compact_blank
    to("/board?#{URI.encode_www_form(query)}")
  end
end
