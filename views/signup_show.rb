require_relative 'components/master'

# Compose a sign-up post: which occurrences, which emoji, and when the bot
# should send it.
class SignupShow < Phlex::HTML
  include Components

  SUGGESTED = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '🚗', '✅', '🙋'].freeze

  def initialize(post:, candidates:, channels:, leader: false, error: nil)
    @post = post
    @candidates = candidates
    @channels = channels
    @leader = leader
    @error = error
  end

  def view_template
    Layout(title: 'Sign-up post', leader: @leader) do
      div(class: 'max-w-3xl flex flex-col gap-5 font-sans text-ink') do
        breadcrumb
        header
        p(role: 'alert', class: 'text-sm text-danger') { @error } if @error
        failure_note if @post.failed?

        div(class: 'grid gap-5 md:grid-cols-[1fr_320px] items-start') do
          div(class: 'flex flex-col gap-5') do
            settings
            options
            add_option if editable?
          end
          preview
        end

        actions
      end
    end
  end

  private

  def editable?
    @leader && @post.editable?
  end

  def breadcrumb
    div(class: 'text-[12px] text-ink/60') do
      a(href: '/signups', class: 'text-accent no-underline hover:underline') { 'Sign-up posts' }
      plain ' / '
      plain(@post.service_date&.strftime('%-d %b') || 'new')
    end
  end

  def header
    div(class: 'flex items-center gap-3 flex-wrap') do
      h1(class: 'font-display font-bold text-xl -tracking-[.015em]') { 'Sign-up post' }
      status_pill
      div(class: 'flex-1')
      if @post.message_link
        a(href: @post.message_link, target: '_blank', rel: 'noopener',
          class: 'board-btn no-underline') { 'View in Discord' }
      end
    end
  end

  def status_pill
    style, label =
      case @post.status
      when 'posted' then @post.closed_at ? ['bg-ink/[.07] text-ink/70', 'closed'] : ['bg-accent-tint text-accent', 'live']
      when 'scheduled' then ['bg-warn-tint text-warn-ink', 'scheduled']
      when 'posting' then ['bg-warn-tint text-warn-ink', 'sending']
      when 'failed' then ['bg-danger-tint text-danger', 'failed']
      when 'closed' then ['bg-ink/[.07] text-ink/70', 'closed']
      else ['bg-ink/[.07] text-ink/70', 'draft']
      end

    span(class: "font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] uppercase #{style}") { label }
  end

  def failure_note
    div(class: 'p-3 rounded-lg border border-danger/30 bg-danger-tint text-[12.5px] text-danger') do
      plain 'Sending failed: '
      plain @post.last_error.to_s
    end
  end

  # --- settings ------------------------------------------------------------

  def settings
    form(method: 'post', action: "/signups/#{@post.id}", class: 'flex flex-col gap-3') do
      input(type: 'hidden', name: '_method', value: 'patch')

      div(class: 'grid grid-cols-2 gap-3') do
        field('Channel') { channel_select }
        field('Ride date') { date_field('service_date', @post.service_date) }
      end

      field('Send at') do
        datetime_field('post_at', @post.post_at)
        span(class: 'text-[11.5px] text-ink/60') { 'The bot posts the message at this time.' }
      end

      field('Intro') { text_field('intro', @post.intro, placeholder: default_intro_hint) }
      field('Footer (optional)') { text_field('outro', @post.outro, placeholder: 'e.g. React by 8am Sunday') }

      button(type: 'submit', class: 'board-btn self-start') { 'Save' } if editable?
    end
  end

  def field(label, &block)
    div(class: 'flex flex-col gap-[5px]') do
      span(class: 'board-label') { label }
      yield
    end
  end

  def text_field(name, value, placeholder: nil)
    input(type: 'text', name: name, value: value.to_s, placeholder: placeholder,
          disabled: !editable?, class: 'board-input')
  end

  def date_field(name, value)
    input(type: 'date', name: name, value: value&.strftime('%Y-%m-%d').to_s,
          disabled: !editable?, class: 'board-input')
  end

  def datetime_field(name, value)
    input(type: 'datetime-local', name: name, value: value&.strftime('%Y-%m-%dT%H:%M').to_s,
          disabled: !editable?, class: 'board-input')
  end

  def channel_select
    select(name: 'channel_id', disabled: !editable?, class: 'board-input') do
      @channels.each do |channel|
        option(value: channel.id, selected: @post.channel_id == channel.id) { "##{channel.name}" }
      end
    end
  end

  def default_intro_hint
    "Rides for #{(@post.service_date || Time.zone.today).strftime('%A %-d %B')} — react below if you need one."
  end

  # --- options -------------------------------------------------------------

  def options
    div(class: 'flex flex-col gap-2.5') do
      div(class: 'flex items-baseline gap-2') do
        span(class: 'board-label') { 'Ride options' }
        span(class: 'text-[11.5px] text-ink/60') { @post.summary }
      end

      if @post.options.empty?
        div(class: 'px-1 py-4 text-[13px] text-ink/65') { 'No options yet. Add one for each ride time.' }
      else
        @post.options.each { |option| option_row(option) }
      end
    end
  end

  def option_row(option)
    form(method: 'post', action: "/signups/#{@post.id}/options/#{option.id}",
         class: 'flex items-center gap-3 px-3 py-2.5 rounded-lg border border-line bg-surface flex-wrap') do
      input(type: 'hidden', name: '_method', value: 'patch')

      span(class: 'text-[22px] leading-none w-8 text-center') { option.display }

      div(class: 'flex-1 min-w-[220px] flex flex-col gap-1') do
        select(name: 'event_id', disabled: !editable?, class: 'board-input') do
          option(value: '', selected: option.event_id.nil?) { 'Pick the ride this books' }
          @candidates.each do |event|
            option(value: event.id, selected: option.event_id == event.id) { candidate_label(event) }
          end
        end
        input(type: 'text', name: 'label', value: option.label.to_s, disabled: !editable?,
              placeholder: 'Line text (defaults to the ride time)', class: 'board-input text-[12px] py-1.5')
      end

      if @post.posted?
        span(class: 'font-mono text-[11px] text-ink/70 whitespace-nowrap') { "#{option.live_reaction_count} reacted" }
      end

      if editable?
        button(type: 'submit', class: 'board-btn') { 'Save' }
        delete_option(option)
      end
    end
  end

  def delete_option(option)
    form(method: 'post', action: "/signups/#{@post.id}/options/#{option.id}", class: 'contents') do
      input(type: 'hidden', name: '_method', value: 'delete')
      button(type: 'submit', title: 'Remove option',
             class: 'border border-danger/25 bg-surface text-danger font-semibold text-xs px-2.5 py-[9px] rounded-[7px] cursor-pointer hover:bg-danger-tint') { '✕' }
    end
  end

  def candidate_label(event)
    "#{event.start_time.strftime('%a %-d %b %-l:%M %p')} — #{event.display_name}"
  end

  def add_option
    div(class: 'flex flex-col gap-2 p-3 rounded-lg border border-line bg-surface-sunk') do
      span(class: 'board-label') { 'Add an option' }
      form(method: 'post', action: "/signups/#{@post.id}/options", class: 'flex flex-col gap-2') do
        div(class: 'flex gap-2 flex-wrap') do
          input(type: 'text', name: 'emoji', required: true, placeholder: 'Emoji',
                class: 'board-input w-28 text-center text-[18px]', list: 'emoji-suggestions')
          datalist(id: 'emoji-suggestions') do
            SUGGESTED.each { |e| option(value: e) }
          end
          select(name: 'event_id', required: true, class: 'board-input flex-1 min-w-[220px]') do
            option(value: '') { 'Pick the ride this books' }
            @candidates.each { |e| option(value: e.id) { candidate_label(e) } }
          end
        end
        input(type: 'text', name: 'label', placeholder: 'Line text (optional)', class: 'board-input text-[12px] py-1.5')
        button(type: 'submit', class: 'board-btn-solid self-start') { 'Add option' }
      end
    end
  end

  # --- preview -------------------------------------------------------------

  # Rendered by the same class the bot uses, so this cannot drift from what
  # actually gets posted.
  def preview
    div(class: 'flex flex-col gap-1.5 md:sticky md:top-4') do
      span(class: 'board-label') { 'What the bot will post' }
      div(class: 'p-3 rounded-lg border border-line bg-surface-sunk') do
        pre(class: 'font-sans text-[12.5px] leading-[1.6] whitespace-pre-wrap') { @post.body }
      end
      if @post.post_at
        span(class: 'text-[11.5px] text-ink/60') do
          "#{@post.posted? ? 'Posted' : 'Sends'} #{@post.post_at.strftime('%a %-d %b at %-l:%M %p')}"
        end
      end
    end
  end

  # --- actions -------------------------------------------------------------

  def actions
    return unless @leader

    div(class: 'flex gap-2 pt-1 flex-wrap border-t border-line pt-4') do
      case @post.status
      when 'draft', 'failed'
        if @post.schedulable?
          post_button('schedule', 'Schedule this post', 'board-btn-solid')
        else
          span(class: 'text-[12.5px] text-ink/65 py-2') { blockers }
        end
      when 'scheduled'
        post_button('unschedule', 'Back to draft', 'board-btn')
      when 'posted'
        if @post.closed_at
          post_button('reopen', 'Reopen', 'board-btn')
        else
          post_button('close', 'Stop tracking', 'board-btn')
          post_button('resync', 'Re-sync from Discord', 'board-btn')
        end
      end

      div(class: 'flex-1')
      delete_post if @post.editable?
    end
  end

  def blockers
    missing = []
    missing << 'add at least one option' if @post.options.empty?
    missing << 'every option needs a ride' unless @post.options.empty? || @post.bound?
    missing << 'set a send time' if @post.post_at.blank?
    missing << 'pick a channel' if @post.channel_id.blank?
    "Before scheduling: #{missing.join(', ')}."
  end

  def post_button(path, label, style)
    form(method: 'post', action: "/signups/#{@post.id}/#{path}", class: 'contents') do
      button(type: 'submit', class: style) { label }
    end
  end

  def delete_post
    form(method: 'post', action: "/signups/#{@post.id}", class: 'contents') do
      input(type: 'hidden', name: '_method', value: 'delete')
      button(type: 'submit', data_confirm: 'Delete this draft?',
             class: 'border border-danger/25 bg-surface text-danger font-semibold text-xs px-3 py-[9px] rounded-[7px] cursor-pointer hover:bg-danger-tint') { 'Delete draft' }
    end
  end
end
