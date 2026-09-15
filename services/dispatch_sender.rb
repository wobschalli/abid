# Delivers queued dispatches. Runs in the BOT process, from the scheduler tick.
#
# The roster was snapshotted by DispatchPlanner in the web process when the
# coordinator pressed send; this only renders it and does the DMing, so an OSRM
# or Discord hiccup never happens inside a Puma request.
class DispatchSender
  SEND_DELAY = 0.4 # opening a DM channel is its own request; stay well inside the limits
  MAX_ATTEMPTS = 3

  def initialize(bot, messenger = nil)
    @bot = bot
    @messenger = messenger
  end

  def pump(limit: 3)
    Dispatch.reap_stalled!
    delivered = 0
    limit.times do
      dispatch = Dispatch.claim! or break
      deliver(dispatch)
      delivered += 1
    end
    delivered
  end

  private

  def deliver(dispatch)
    dispatch.messages.pending.find_each do |message|
      send_one(message)
      sleep SEND_DELAY
    end
    dispatch.finalise!
    notify_requester(dispatch)
  rescue StandardError => e
    warn "dispatch #{dispatch.id} failed: #{e.class}: #{e.message}"
    dispatch.update(status: 'failed', finished_at: Time.zone.now)
  end

  def send_one(message)
    return skip(message, 'no discord id') if message.discord_id.blank?
    return skip(message, 'too many attempts') if message.attempts >= MAX_ATTEMPTS

    body = DriverBriefing.new(message.roster).to_text
    dm = @bot.user(message.discord_id).dm(body)

    message.update!(status: 'sent', body: body, sent_at: Time.zone.now,
                    discord_message_id: dm&.id, attempts: message.attempts + 1,
                    error_class: nil, error_message: nil)
  rescue StandardError => e
    # The realistic failure is Discord 50007, "cannot send messages to this
    # user" — DMs closed or no mutual server. That is not a bug, and must never
    # take the rest of the run down. Never auto-retried: a privacy setting is
    # not going to change in thirty seconds.
    message.update!(status: 'failed', attempts: message.attempts + 1,
                    error_class: e.class.name, error_message: e.message.to_s.first(500))
    warn "DM to #{message.driver_name} failed: #{e.class}: #{e.message}"
  end

  def skip(message, reason)
    message.update!(status: 'failed', error_class: 'Skipped', error_message: reason)
  end

  def notify_requester(dispatch)
    return if @messenger.nil? || dispatch.requested_by.nil?

    @messenger.dm_user(dispatch.requested_by, dispatch.summary_line)
  rescue StandardError => e
    warn "could not notify requester: #{e.class}: #{e.message}"
  end
end
