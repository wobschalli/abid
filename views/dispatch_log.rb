require_relative 'components/master'

# What was actually sent, to whom, when — and the exact text, so a failed DM
# can be read out and passed on by hand.
class DispatchLog < Phlex::HTML
  include Components

  def initialize(event:, dispatches:, leader: false)
    @event = event
    @dispatches = dispatches
    @leader = leader
  end

  def view_template
    Layout(title: "Dispatch log — #{@event.name}", leader: @leader) do
      div(class: 'max-w-3xl flex flex-col gap-5 font-sans text-ink') do
        breadcrumb
        h1(class: 'font-display font-bold text-2xl -tracking-[.015em]') { 'Dispatch log' }
        @dispatches.empty? ? empty_note : list
      end
    end
  end

  private

  def breadcrumb
    div(class: 'text-[12px] text-ink/60') do
      a(href: "/events/#{@event.id}", class: 'text-accent no-underline hover:underline') { @event.name.to_s }
      plain ' / dispatch log'
    end
  end

  def empty_note
    div(class: 'px-1 py-6 text-[13px] text-ink/65') { 'Nothing has been sent for this event yet.' }
  end

  def list
    div(class: 'flex flex-col gap-4') { @dispatches.each { |d| dispatch_card(d) } }
  end

  def dispatch_card(dispatch)
    div(class: 'flex flex-col gap-2 p-3.5 rounded-lg border border-line bg-surface') do
      div(class: 'flex items-center gap-2.5 flex-wrap') do
        span(class: 'font-semibold text-[13px]') { "Attempt #{dispatch.attempt}" }
        status_pill(dispatch)
        span(class: 'board-meta') { header_meta(dispatch) }
      end
      dispatch.messages.sort_by(&:driver_name).each { |m| message_row(m) }
    end
  end

  def header_meta(dispatch)
    [
      dispatch.requested_at&.strftime('%-d %b %-l:%M %p'),
      ("by #{dispatch.requested_by.display_name}" if dispatch.requested_by),
      (dispatch.scope == 'all' ? 'everyone' : 'changed only')
    ].compact.join(' · ')
  end

  def status_pill(dispatch)
    style, label =
      case dispatch.status
      when 'sent' then ['bg-accent-tint text-accent', 'sent']
      when 'partial' then ['bg-warn-tint text-warn-ink', 'partial']
      when 'failed' then ['bg-danger-tint text-danger', 'failed']
      when 'sending' then ['bg-warn-tint text-warn-ink', 'sending']
      else ['bg-ink/[.07] text-ink/70', 'queued']
      end

    span(class: "font-mono text-[9.5px] font-semibold tracking-[.06em] px-[7px] py-[3px] rounded-[5px] uppercase #{style}") { label }
  end

  def message_row(message)
    details(class: 'rounded-md border border-line-soft') do
      summary(class: 'flex items-center gap-2 px-2.5 py-2 cursor-pointer text-[12.5px]') do
        span(class: 'font-medium capitalize flex-1') { message.driver_name.to_s }
        span(class: 'board-meta') { "#{message.rider_names.size} #{'rider'.pluralize(message.rider_names.size)}" }
        message_pill(message)
      end
      body_block(message)
    end
  end

  # Delivered and read back are different facts and get different pills. A
  # message we sent at 8:02 that nobody ever acknowledged used to look identical
  # to one the driver confirmed thirty seconds later, which is the whole
  # question this page gets opened to answer.
  def message_pill(message)
    style, label =
      if message.acknowledged?
        ['bg-accent-tint text-accent', "✓ #{message.acknowledged_at.strftime('%-l:%M %p')}"]
      else
        case message.status
        when 'sent' then ['bg-ink/[.07] text-ink/70', "sent #{message.sent_at&.strftime('%-l:%M %p')}".strip]
        when 'failed' then ['bg-danger-tint text-danger', 'failed']
        when 'skipped' then ['bg-ink/[.07] text-ink/70', 'skipped']
        else ['bg-ink/[.07] text-ink/70', 'pending']
        end
      end

    span(
      title: message.acknowledged? ? 'pressed “Got it” on their DM' : nil,
      class: "font-mono text-[9.5px] font-semibold px-[7px] py-[3px] rounded-[5px] #{style}"
    ) { label }
  end

  def body_block(message)
    div(class: 'px-2.5 pb-2.5 flex flex-col gap-2') do
      if message.failed?
        div(class: 'text-[12px] text-danger') do
          plain "#{message.error_class}: #{message.error_message}"
          if message.phone.present?
            plain " — reach them on #{message.phone}"
          end
        end
      end

      if message.body.present?
        pre(class: 'p-2.5 rounded-md bg-surface-sunk font-sans text-[12px] leading-[1.55] whitespace-pre-wrap') do
          message.body
        end
      else
        span(class: 'text-[12px] text-ink/60') { rider_summary(message) }
      end
    end
  end

  # Skipped and pending messages have no body yet, but the roster snapshot is
  # still there.
  def rider_summary(message)
    names = message.rider_names
    return 'No riders in this car.' if names.empty?

    names.join(', ')
  end
end
