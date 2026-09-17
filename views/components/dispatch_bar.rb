require_relative 'components'
require_relative 'board_helpers'

# Pre-flight and the send button, between the car grid and the footer.
class Components::DispatchBar < Phlex::HTML
  include BoardHelpers

  def initialize(board:, readiness:, status:, leader: false, tab: :details)
    @board = board
    @readiness = readiness
    @status = status
    @leader = leader
    @tab = tab
  end

  def view_template
    div(class: 'flex-none flex items-center gap-3 px-5 py-2.5 border-t border-line bg-surface flex-wrap') do
      state
      div(class: 'flex-1')
      last_sent
      buttons if @leader
    end
    findings if @readiness.findings.any?
  end

  private

  def state
    if @readiness.ready?
      div(class: 'flex items-center gap-2 text-[12.5px] font-medium text-accent') do
        span(class: 'w-1.5 h-1.5 rounded-full bg-accent flex-none')
        plain ready_label
      end
    else
      div(class: 'flex items-center gap-2 text-[12.5px] font-medium text-danger') do
        span(class: 'w-1.5 h-1.5 rounded-full bg-danger flex-none')
        plain "#{@readiness.blocking.size} #{'thing'.pluralize(@readiness.blocking.size)} to fix before sending"
      end
    end
  end

  def ready_label
    count = @status.stale_driver_rides.size
    return 'All drivers are up to date' if count.zero?

    "Ready — #{count} #{'driver'.pluralize(count)} to tell"
  end

  def last_sent
    # Say so the moment it is queued. The bot polls every 30 seconds, so
    # otherwise the press produced no visible change at all and read as a
    # button that does nothing.
    if @status.queued_count.positive?
      return span(class: 'font-mono text-[11px] text-accent') do
        "queued for #{@status.queued_count} #{'driver'.pluralize(@status.queued_count)} — the bot sends within 30 seconds"
      end
    end

    return unless @status.anything_sent?

    bits = []
    bits << "last sent #{@status.last_sent_at.strftime('%-l:%M %p')}" if @status.last_sent_at
    # The question at 8am is not "did it send" but "who has not confirmed".
    bits << "#{@status.confirmed_count} confirmed" if @status.confirmed_count.positive?
    bits << "#{@status.awaiting_count} not confirmed yet" if @status.awaiting_count.positive?
    bits << "#{@status.changed_count} changed since" if @status.changed_count.positive?
    bits << "#{@status.failed_count} failed" if @status.failed_count.positive?

    span(class: 'font-mono text-[11px] text-ink/70') { bits.join(' · ') }
  end

  def buttons
    count = @status.stale_driver_rides.size

    a(href: "/events/#{@board.event.id}/dispatches",
      class: 'board-btn no-underline') { 'Log' } if @status.anything_sent?

    send_form('changed', count.zero? ? 'Nothing to send' : "Send to #{count} #{'driver'.pluralize(count)}",
              primary: @readiness.ready?, disabled: count.zero?)

    if @status.anything_sent?
      send_form('all', 'Resend to all', primary: false, disabled: false)
    end
  end

  def send_form(scope, label, primary:, disabled:)
    action_form('dispatch', scope: scope, class: 'contents') do
      button(
        type: 'submit',
        disabled: disabled,
        data_confirm: confirm_text(scope),
        class: "#{primary ? 'board-btn-solid' : 'board-btn'} #{disabled ? 'opacity-55' : ''}"
      ) { label }
    end
  end

  def confirm_text(scope)
    who = scope == 'all' ? 'every driver' : 'each driver with changes'
    warning = @readiness.ready? ? '' : " There are #{@readiness.blocking.size} unresolved problems."
    "DM #{who} their riders, pickups and phone numbers?#{warning}"
  end

  def findings
    div(class: 'flex-none flex flex-col gap-1 px-5 pb-2.5 bg-surface') do
      @readiness.findings.each { |finding| finding_row(finding) }
    end
  end

  def finding_row(finding)
    error = finding.severity == :error
    div(class: "flex items-start gap-2 text-[12px] #{error ? 'text-danger' : 'text-warn-ink'}") do
      span(class: "w-1.5 h-1.5 mt-1.5 rounded-full flex-none #{error ? 'bg-danger' : 'bg-warn'}")
      plain finding.message
    end
  end
end
