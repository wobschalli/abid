class Dispatch < ApplicationRecord
  # One press of "Send to drivers", and the outbox row the bot claims.
  #
  # A Postgres table rather than Redis or an HTTP call to the bot: Postgres is
  # the only thing the two processes already share, the state machine has to
  # exist regardless because DMs must not go out twice, and if the bot is down
  # when the coordinator presses send, the row waits and goes out on boot —
  # which an HTTP call cannot do.
  STATUSES = %w[queued sending sent partial failed].freeze
  SCOPES = %w[changed all].freeze
  STALE_AFTER = 10.minutes

  belongs_to :event
  belongs_to :requested_by, class_name: 'User', optional: true
  has_many :messages, class_name: 'DispatchMessage', dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :scope, inclusion: { in: SCOPES }

  scope :recent, -> { order(requested_at: :desc) }
  scope :finished, -> { where(status: %w[sent partial failed]) }

  # The standard Postgres work-queue claim: safe against a crash between SELECT
  # and UPDATE, and against a second bot process.
  def self.claim!
    find_by_sql(<<~SQL).first
      UPDATE dispatches
         SET status = 'sending', started_at = now(), updated_at = now()
       WHERE id = (
               SELECT id FROM dispatches
                WHERE status = 'queued'
                ORDER BY requested_at
                  FOR UPDATE SKIP LOCKED
                LIMIT 1)
      RETURNING *
    SQL
  end

  # A process killed mid-send leaves rows stuck in 'sending'. Individual
  # messages already record their own status, so re-queuing only retries the
  # ones that never went out.
  def self.reap_stalled!
    where(status: 'sending').where(started_at: ...STALE_AFTER.ago)
                            .update_all(status: 'queued', started_at: nil, updated_at: Time.zone.now)
  end

  def finalise!
    counts = messages.group(:status).count
    sent = counts['sent'].to_i
    failed = counts['failed'].to_i

    final = if failed.zero? then 'sent'
            elsif sent.positive? then 'partial'
            else 'failed'
            end

    update!(status: final, finished_at: Time.zone.now)
  end

  def summary_line
    counts = messages.group(:status).count
    parts = ["#{counts['sent'].to_i} sent"]
    parts << "#{counts['failed'].to_i} failed" if counts['failed'].to_i.positive?
    parts << "#{counts['skipped'].to_i} skipped" if counts['skipped'].to_i.positive?
    "#{event.display_name}: #{parts.join(', ')}"
  end

  def failures
    messages.where(status: 'failed')
  end
end
