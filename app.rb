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
    ensure_logged_in
  end

  get '/' do
    phlex Home.new
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
