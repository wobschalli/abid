require_relative 'components/master'

class UsersIndex < Phlex::HTML
  include Components

  FILTERS = [
    ['all', 'Everyone'],
    ['drivers', 'Drivers'],
    ['leaders', 'Leaders'],
    ['missing', 'Missing details']
  ].freeze

  def initialize(users:, load:, filter: 'all', query: nil, counts: {}, leader: false)
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
      span(class: 'board-meta') { "#{@counts['all']} people" }
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
    query = { filter: (value unless value == 'all'), q: @query.presence }.compact
    query.empty? ? '/users' : "/users?#{URI.encode_www_form(query)}"
  end

  # GET so it is bookmarkable and survives a no-JS submit, matching the board's
  # queue filter.
  def search_form
    form(method: 'get', action: '/users', class: 'flex gap-2 items-center') do
      input(type: 'hidden', name: 'filter', value: @filter) unless @filter == 'all'
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

  def row(user)
    a(
      href: "/users/#{user.id}",
      class: 'flex items-center gap-3 px-3 py-2.5 rounded-lg border border-line bg-surface ' \
             'no-underline text-ink hover:border-accent transition-colors'
    ) do
      div(class: 'flex-1 min-w-0 flex flex-col gap-0.5') do
        div(class: 'flex items-baseline gap-2 flex-wrap') do
          span(class: 'font-semibold text-[13px] capitalize') { user.display_name }
          badges(user)
        end
        span(class: 'board-meta') { meta(user) }
      end
      span(class: 'font-mono text-[11px] text-ink/70 text-right whitespace-nowrap') { load_label(user) }
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
