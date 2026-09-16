require_relative 'components/master'

class UsersIndex < Phlex::HTML
  include Components

  # 'Everyone' is gone on purpose: the Discord sync brings in everyone who has
  # ever joined the server, so an unfiltered list of 271 is not a roster anyone
  # works from. Active is the default and the first thing you see.
  FILTERS = [
    ['active', 'Active'],
    ['other', 'Other'],
    ['drivers', 'Drivers'],
    ['riders', 'Riders'],
    ['missing', 'Missing details']
  ].freeze

  def initialize(users:, load:, filter: 'active', query: nil, counts: {}, leader: false)
    @users = users
    @load = load
    @filter = filter
    @query = query
    @counts = counts
    @leader = leader
  end

  def view_template
    Layout(title: 'Members', leader: @leader) do
      div(class: 'max-w-4xl flex flex-col gap-5 font-sans text-ink') do
        header
        controls
        @users.empty? ? empty_note : list
      end
    end
  end

  private

  def header
    div(class: 'flex items-baseline gap-3 flex-wrap') do
      h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { 'Members' }
      total = @counts['active'].to_i + @counts['other'].to_i
      span(class: 'board-meta') { "#{@counts['active'].to_i} active of #{total} in the server" }
    end
  end

  def controls
    div(class: 'flex items-center gap-3 flex-wrap') do
      tabs
      div(class: 'flex-1')
      search_form
    end
  end

  def tabs
    div(class: 'flex gap-1 p-[3px] bg-ink/5 rounded-lg') do
      FILTERS.each do |value, label|
        current = @filter == value
        a(
          href: filter_href(value),
          class: [
            'cursor-pointer font-semibold text-[11.5px] px-[11px] py-1.5 rounded-md no-underline whitespace-nowrap',
            current ? 'bg-surface text-ink shadow-[0_1px_2px_rgba(23,32,28,.12)]' : 'bg-transparent text-ink/70 hover:text-ink'
          ].join(' ')
        ) do
          plain label
          count = @counts[value]
          if count.to_i.positive?
            whitespace
            span(class: 'opacity-60 font-mono text-[10px]') { count.to_s }
          end
        end
      end
    end
  end

  def filter_href(value)
    query = { filter: (value unless value == 'active'), q: @query.presence }.compact
    query.empty? ? '/users' : "/users?#{URI.encode_www_form(query)}"
  end

  # GET so it is bookmarkable and survives a no-JS submit, matching the board's
  # queue filter.
  def search_form
    form(method: 'get', action: '/users', class: 'flex gap-2 items-center') do
      input(type: 'hidden', name: 'filter', value: @filter) unless @filter == 'active'
      input(type: 'search', name: 'q', value: @query.to_s, placeholder: 'Search by name',
            autocomplete: 'off', class: 'board-input w-56 text-[12.5px] py-2')
    end
  end

  def empty_note
    div(class: 'px-1 py-6 text-[13px] text-ink/65') do
      if @query.present?
        "Nobody matches #{@query.inspect}."
      else
        'Nobody here yet. Members are created automatically when they join the Discord server.'
      end
    end
  end

  def list
    div(class: 'flex flex-col gap-1.5') { @users.each { |user| row(user) } }
  end

  # A div rather than a link wrapping everything, because the active toggle is a
  # form and a form cannot live inside an anchor. The name is the link instead.
  def row(user)
    div(class: 'flex items-center gap-3 px-3 py-2.5 rounded-lg border border-line bg-surface ' \
               'hover:border-accent transition-colors') do
      a(href: "/users/#{user.id}",
        class: 'flex-1 min-w-0 flex flex-col gap-0.5 no-underline text-ink') do
        div(class: 'flex items-baseline gap-2 flex-wrap') do
          span(class: 'font-semibold text-[13px] capitalize') { user.display_name }
          badges(user)
        end
        span(class: 'board-meta') { meta(user) }
      end
      span(class: 'font-mono text-[11px] text-ink/70 text-right whitespace-nowrap') { load_label(user) }
      active_toggle(user) if @leader
    end
  end

  # One click, and it comes back to the tab and search you were on — marking a
  # dozen people active in a row should not bounce you to the top of an
  # unfiltered list each time.
  def active_toggle(user)
    form(method: 'post', action: "/users/#{user.id}/active", class: 'contents') do
      input(type: 'hidden', name: 'active', value: user.active? ? '0' : '1')
      input(type: 'hidden', name: 'filter', value: @filter.to_s)
      input(type: 'hidden', name: 'q', value: @query.to_s)
      button(
        type: 'submit',
        title: user.active? ? 'Mark as not active' : 'Mark as active this year',
        class: [
          'shrink-0 cursor-pointer font-mono text-[9.5px] font-semibold tracking-[.06em] uppercase',
          'px-[9px] py-[5px] rounded-md border transition-colors',
          user.active? ? 'border-accent bg-accent-tint text-accent hover:bg-accent-tint-strong'
                       : 'border-line bg-surface text-ink/45 hover:text-ink hover:border-ink/30'
        ].join(' ')
      ) { user.active? ? 'active' : '+ active' }
    end
  end

  def badges(user)
    pill('leader', 'bg-accent-tint text-accent') if user.leader
    pill("#{user.capacity} seats", 'bg-ink/[.07] text-ink/70') if user.can_drive?
    if user.missing_details?
      pill("no #{user.missing_details.join(', no ')}", 'bg-warn-tint text-warn-ink')
    end
  end

  def pill(text, style)
    span(class: "font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] uppercase #{style}") do
      text
    end
  end

  def meta(user)
    [
      user.location&.name,
      user.location&.zone,
      user.phone.presence,
      user.class_of
    ].compact.join(' · ').presence || 'no details yet'
  end

  def load_label(user)
    summary = @load.summary(user)
    return '—' if summary.nil?

    heavy = @load.heavy_load?(user)
    span(class: heavy ? 'text-warn-ink font-semibold' : '') { summary }
  end
end
