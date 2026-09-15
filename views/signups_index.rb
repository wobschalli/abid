require_relative 'components/master'

class SignupsIndex < Phlex::HTML
  include Components

  def initialize(posts:, channels:, leader: false)
    @posts = posts
    @channels = channels
    @leader = leader
  end

  def view_template
    Layout(title: 'Sign-up posts', leader: @leader) do
      div(class: 'max-w-3xl flex flex-col gap-5 font-sans text-ink') do
        header
        how_it_works
        new_post_form if @leader
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

  def new_post_form
    form(method: 'post', action: '/signups',
         class: 'flex gap-2 items-end flex-wrap p-3 rounded-lg border border-line bg-surface') do
      div(class: 'flex flex-col gap-[5px]') do
        span(class: 'board-label') { 'Channel' }
        select(name: 'channel_id', required: true, class: 'board-input') do
          @channels.each { |c| option(value: c.id) { "##{c.name}" } }
        end
      end
      div(class: 'flex flex-col gap-[5px]') do
        span(class: 'board-label') { 'Ride date' }
        input(type: 'date', name: 'service_date', class: 'board-input',
              value: default_date.strftime('%Y-%m-%d'))
      end
      button(type: 'submit', class: 'board-btn-solid') { 'New post' }
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

  def meta(post)
    [
      "##{post.channel&.name}",
      post.summary,
      ("#{post.reaction_count} reactions" if post.posted?)
    ].compact.join(' · ')
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
