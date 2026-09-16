require_relative 'components/master'

# Compose a sign-up post: which occurrences, which emoji, and when the bot
# should send it.
class SignupShow < Phlex::HTML
  include Components

  # The palette offered by default. Anything at all can still be typed into the
  # box next to it, and the server's own emoji are appended to this from the
  # database, so this list is a starting point rather than a limit.
  SUGGESTED = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣', '7️⃣', '8️⃣', '9️⃣', '🔟',
               '🚗', '🚙', '🚐', '🕐', '🕕', '🙋', '✅', '❌', '🌅', '🌆',
               '☀️', '🌙', '⛪', '🍽️', '📖', '🎒', '🙏', '💺'].freeze

  def initialize(post:, candidates:, channels:, server_emojis: [], leader: false, error: nil)
    @post = post
    @candidates = candidates
    @channels = channels
    @server_emojis = server_emojis
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
        div(class: 'flex-1')
        # For when the ride date is changed, or an event is added to that day
        # after the post was made.
        post_button('fill', 'Fill from this date', 'board-btn') if editable? && @leader
      end

      if @post.options.empty?
        div(class: 'px-1 py-4 text-[13px] text-ink/65') do
          'No rides on this date yet. Change the ride date above, or add one below.'
        end
      else
        @post.options.each { |option| option_row(option) }
      end
    end
  end

  def option_row(option)
    form(method: 'post', action: "/signups/#{@post.id}/options/#{option.id}",
         class: 'flex items-center gap-3 px-3 py-2.5 rounded-lg border border-line bg-surface flex-wrap') do
      input(type: 'hidden', name: '_method', value: 'patch')

      span(class: 'text-[22px] leading-none w-8 flex items-center justify-center shrink-0') do
        # A custom emoji has no character to print. `option.display` falls back
        # to ":name:", which at 22px overflowed this box as raw text.
        if option.emoji_discord_id.present?
          custom_emoji_image(option.emoji_discord_id, option.emoji_name)
        else
          plain option.display
        end
      end

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

  # A grid of radio buttons rather than a JS widget. Picking an emoji is then a
  # plain form field: it needs no build step, survives JS being off, and posts
  # through the same route as the text box.
  #
  # The `peer-checked` styling is what makes a radio look like a pressed key —
  # the input itself is visually hidden but still focusable, so keyboard and
  # screen-reader users get a normal radio group.
  def emoji_picker
    div(class: 'flex flex-col gap-2') do
      span(class: 'board-label') { 'Pick an emoji' }
      div(class: 'flex flex-wrap gap-1') do
        SUGGESTED.each { |char| emoji_choice(char) { plain char } }
      end

      next if @server_emojis.empty?

      span(class: 'board-label pt-1') { "This server's emoji" }
      div(class: 'flex flex-wrap gap-1 max-h-40 overflow-y-auto') do
        @server_emojis.each do |emoji|
          # `<:name:id>` is exactly what Discord puts in message content, and
          # what EmojiKey.parse already understands.
          emoji_choice("<:#{emoji.name}:#{emoji.discord_id}>", title: ":#{emoji.name}:") do
            custom_emoji_image(emoji.discord_id, emoji.name)
          end
        end
      end
    end
  end

  # The body is the literal text Discord receives, so a custom emoji appears in
  # it as `<:name:id>`. Printing that verbatim is accurate about the content but
  # wrong about the appearance, and this panel is captioned "what the bot will
  # post" — so swap each token for the image Discord itself would show.
  def preview_body
    body = @post.body.to_s
    pos = 0

    while (match = Signup::EmojiKey::CUSTOM_PATTERN.match(body, pos))
      plain body[pos...match.begin(0)] if match.begin(0) > pos
      custom_emoji_image(match[3], match[2])
      pos = match.end(0)
    end

    plain body[pos..] if pos < body.length
  end

  def custom_emoji_image(discord_id, name)
    # `inline-block` is load-bearing: Tailwind's preflight sets images to
    # `display: block`, which in the preview put every custom emoji on a line of
    # its own instead of beside the text it belongs to.
    img(src: "https://cdn.discordapp.com/emojis/#{discord_id}.png?size=32",
        alt: ":#{name}:", title: ":#{name}:", loading: 'lazy',
        class: 'inline-block align-text-bottom w-[22px] h-[22px] object-contain')
  end

  def emoji_choice(value, title: nil, &block)
    label(class: 'cursor-pointer', title: title || value) do
      input(type: 'radio', name: 'emoji_pick', value: value, class: 'sr-only peer')
      span(class: 'flex items-center justify-center w-9 h-9 text-[19px] leading-none rounded-lg ' \
                  'border border-line bg-surface hover:bg-surface-sunk ' \
                  'peer-checked:border-accent peer-checked:bg-accent-tint ' \
                  'peer-focus-visible:ring-2 peer-focus-visible:ring-accent', &block)
    end
  end

  def candidate_label(event)
    "#{event.start_time.strftime('%a %-d %b %-l:%M %p')} — #{event.display_name}"
  end

  def add_option
    div(class: 'flex flex-col gap-2 p-3 rounded-lg border border-line bg-surface-sunk') do
      span(class: 'board-label') { 'Add an option' }
      form(method: 'post', action: "/signups/#{@post.id}/options", class: 'flex flex-col gap-2') do
        emoji_picker
        div(class: 'flex gap-2 flex-wrap') do
          input(type: 'text', name: 'emoji', placeholder: 'or type any emoji',
                class: 'board-input w-40 text-center text-[16px]')
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
        pre(class: 'font-sans text-[12.5px] leading-[1.6] whitespace-pre-wrap') { preview_body }
      end
      if @post.post_at
        span(class: 'text-[11.5px] text-ink/60') do
          "#{@post.posted? ? 'Posted' : 'Sends'} #{@post.post_at.strftime('%a %-d %b at %-l:%M %p')}"
        end
      end
      send_status
    end
  end

  # The bot polls every 30 seconds, so a post does not leave the moment you
  # press the button — say so, rather than letting it look broken.
  #
  # And if its time came and went with nothing happening, nothing is draining
  # the queue. Without this a stopped bot is indistinguishable from a slow one,
  # and there is no bot heartbeat anywhere else in the UI.
  def send_status
    return unless @post.status == 'scheduled' && @post.post_at

    overdue = @post.post_at < 2.minutes.ago
    span(class: "text-[11.5px] #{overdue ? 'text-warn-ink' : 'text-ink/60'}") do
      if overdue
        'Still waiting on the bot — is it running?'
      else
        'The bot sends this within 30 seconds.'
      end
    end
  end

  # --- actions -------------------------------------------------------------

  def actions
    return unless @leader

    div(class: 'flex gap-2 pt-1 flex-wrap border-t border-line pt-4') do
      case @post.status
      when 'draft', 'failed'
        if @post.ready_to_send?
          post_button('post-now', 'Post now', 'board-btn-solid')
          post_button('schedule', 'Schedule for later', 'board-btn') if @post.post_at.present?
        else
          span(class: 'text-[12.5px] text-ink/65 py-2') { blockers }
        end
      when 'scheduled'
        post_button('post-now', 'Post now', 'board-btn-solid')
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

  # What is still missing before it can go out at all. A send time is no longer
  # on this list: "Post now" supplies one, so naming it here would describe a
  # blocker that is not blocking anything.
  def blockers
    missing = []
    missing << 'add at least one ride' if @post.options.empty?
    missing << 'every emoji needs a ride' unless @post.options.empty? || @post.bound?
    missing << 'pick a channel' if @post.channel_id.blank?
    "Before sending: #{missing.join(', ')}."
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
