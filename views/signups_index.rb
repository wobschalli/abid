require_relative 'components/master'

class SignupsIndex < Phlex::HTML
  include Components

  def initialize(posts:, channels:, needing_signup: [], leader: false)
    @posts = posts
    @channels = channels
    @needing_signup = needing_signup
    @leader = leader
  end

  def view_template
    Layout(title: 'Sign-up posts', leader: @leader) do
      div(class: 'max-w-3xl flex flex-col gap-5 font-sans text-ink') do
        header
        how_it_works
        if @leader
          dates_needing_signup
          other_date_form
        end
        @posts.empty? ? empty_note : list
      end
    end
  end

  private

  def header
    div(class: 'flex items-center gap-3 flex-wrap') do
      h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { 'Sign-up posts' }
    end
  end

  def how_it_works
    div(class: 'p-3.5 rounded-lg border border-line bg-surface-sunk text-[12.5px] leading-[1.6] text-ink/75') do
      plain 'Build a post here, give each ride time its own emoji, and choose when the bot should send it. '
      plain 'When people react, they land on that ride\'s board automatically.'
    end
  end

  # One button per ride date that has no post yet. The old form asked for a
  # channel and a date and then handed back an empty post to wire up by hand;
  # every one of those answers is already known, so this just makes the post.
  def dates_needing_signup
    return if @needing_signup.empty?

    div(class: 'flex flex-col gap-2') do
      span(class: 'board-label') { 'Coming up, with no sign-up yet' }
      @needing_signup.each { |date, events| needs_signup_row(date, events) }
    end
  end

  def needs_signup_row(date, events)
    form(method: 'post', action: '/signups',
         class: 'flex items-center gap-3 px-3.5 py-3 rounded-lg border border-line bg-surface flex-wrap') do
      input(type: 'hidden', name: 'service_date', value: date.strftime('%Y-%m-%d'))

      div(class: 'flex-1 min-w-0 flex flex-col gap-0.5') do
        span(class: 'font-semibold text-[13.5px]') { date.strftime('%A %-d %B') }
        span(class: 'board-meta') { events.map { |e| ride_label(e) }.join(' · ') }
      end
      channel_field
      button(type: 'submit', class: 'board-btn-solid') { 'Create sign-up' }
    end
  end

  def ride_label(event)
    [event.start_time&.strftime('%-l:%M %p'), event.name].compact_blank.join(' ')
  end

  # With a single channel there is nothing to choose, and this install is
  # deliberately scoped to one. Only ask when the answer is not already known.
  def channel_field
    if @channels.size == 1
      input(type: 'hidden', name: 'channel_id', value: @channels.first.id)
    else
      # `board-input` is width:100%, which on a flex row makes the select eat
      # the whole line and push everything else onto the next one.
      select(name: 'channel_id', required: true, class: 'board-input w-auto shrink-0 py-1.5 text-[12px]') do
        @channels.each { |c| option(value: c.id) { "##{c.name}" } }
      end
    end
  end

  # The escape hatch: a date the list above does not offer.
  def other_date_form
    details(class: 'text-[12.5px]') do
      summary(class: 'cursor-pointer text-ink/65 hover:text-ink') { 'Another date' }
      form(method: 'post', action: '/signups',
           class: 'flex gap-2 items-end flex-wrap pt-2.5') do
        channel_field
        input(type: 'date', name: 'service_date', class: 'board-input',
              value: default_date.strftime('%Y-%m-%d'))
        button(type: 'submit', class: 'board-btn') { 'Create' }
      end
    end
  end

  def default_date
    today = Time.zone.today
    today + ((0 - today.wday) % 7)
  end

  def empty_note
    div(class: 'px-1 py-6 text-[13px] text-ink/65') { 'No sign-up posts yet.' }
  end

  def list
    div(class: 'flex flex-col gap-2') { @posts.each { |post| row(post) } }
  end

  def row(post)
    a(
      href: "/signups/#{post.id}",
      class: 'flex items-center gap-3 px-3.5 py-3 rounded-lg border border-line bg-surface no-underline text-ink hover:border-accent'
    ) do
      div(class: 'flex-1 min-w-0 flex flex-col gap-1') do
        div(class: 'flex items-center gap-2 flex-wrap') do
          span(class: 'text-[15px]') { post.options.map(&:display).join(' ').presence || '—' }
          status_pill(post)
        end
        span(class: 'board-meta') { meta(post) }
      end
      span(class: 'font-mono text-[11px] text-ink/60 text-right') { timing(post) }
    end
  end

  # Name the rides rather than counting them. "2 options" never said which two,
  # which is the one thing you want to know from a list.
  def meta(post)
    rides = post.options.filter_map(&:event).map { |e| ride_label(e) }

    [
      post.service_date&.strftime('%a %-d %b'),
      rides.presence&.join(' · ') || 'no rides yet',
      ("#{post.reaction_count} reactions" if post.posted?)
    ].compact.join(' — ')
  end

  def timing(post)
    return post.posted_at.strftime('%-d %b %-l:%M %p') if post.posted?
    return post.post_at.strftime('%-d %b %-l:%M %p') if post.post_at

    'no send time'
  end

  def status_pill(post)
    style, label =
      case post.status
      when 'posted' then post.closed_at ? ['bg-ink/[.07] text-ink/70', 'closed'] : ['bg-accent-tint text-accent', 'live']
      when 'scheduled' then ['bg-warn-tint text-warn-ink', 'scheduled']
      when 'posting' then ['bg-warn-tint text-warn-ink', 'sending']
      when 'failed' then ['bg-danger-tint text-danger', 'failed']
      else ['bg-ink/[.07] text-ink/70', 'draft']
      end

    span(class: "font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] uppercase #{style}") { label }
  end
end
