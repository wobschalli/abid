class SignupPost < ApplicationRecord
  # A sign-up message the bot composes and posts to Discord at a scheduled
  # time, then watches the reactions on.
  #
  # Each option is an emoji bound to one occurrence: "react 1️⃣ for the 9:00am
  # ride, 2️⃣ for the 10:30am". Discord can tell us which emoji are on the
  # message and how many people used each; only signup_options records what any
  # of them mean.
  STATUSES = %w[draft scheduled posting posted closed failed].freeze

  # A post left in `posting` this long lost its process mid-send.
  STALE_POSTING_AFTER = 2.minutes

  belongs_to :channel
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :options, -> { order(:position) },
           class_name: 'SignupOption', dependent: :destroy, inverse_of: :signup_post
  has_many :events, through: :options

  validates :status, inclusion: { in: STATUSES }
  validates :discord_message_id, uniqueness: true, allow_nil: true
  validate :post_at_required_when_scheduled

  scope :recent, -> { order(Arel.sql('COALESCE(post_at, created_at) DESC')) }
  scope :tracking, -> { where(status: 'posted', closed_at: nil) }
  scope :editable, -> { where(status: %w[draft failed]) }
  # The bot's work queue.
  scope :due, -> { where(status: 'scheduled').where(post_at: ..Time.zone.now).order(:post_at) }
  scope :stale_posting, -> { where(status: 'posting').where(updated_at: ...STALE_POSTING_AFTER.ago) }
  scope :reconcile_requested, lambda {
    tracking.where('reconcile_requested_at > COALESCE(reconciled_at, to_timestamp(0))')
  }
  # Asked to be unsent and not yet unsent. Includes `closed` because stopping
  # tracking does not remove the message from the channel — a closed post is
  # still something you might need to take down.
  scope :revoke_requested, lambda {
    where.not(revoke_requested_at: nil)
         .where(status: %w[posted closed])
         .where.not(discord_message_id: nil)
  }

  def draft?      = status == 'draft'
  def scheduled?  = status == 'scheduled'
  def posted?     = status == 'posted'
  def failed?     = status == 'failed'
  def editable?   = %w[draft failed].include?(status)
  def open?       = posted? && closed_at.nil?

  # Every emoji knows which occurrence it books.
  def bound?
    opts = options.loaded? ? options : options.reload
    opts.any? && opts.all? { |o| o.event_id.present? }
  end

  # Everything a post needs to go out at all. Separate from `schedulable?`
  # because "Post now" supplies the send time itself, so demanding one up front
  # would block the one action that does not need it.
  def ready_to_send?
    editable? && bound? && channel_id.present?
  end

  def schedulable?
    ready_to_send? && post_at.present?
  end

  def body
    Signup::MessageRenderer.new(self).to_s
  end

  def schedule!
    return false unless schedulable?

    update!(status: 'scheduled', last_error: nil)
  end

  def unschedule!
    return false unless scheduled?

    update!(status: 'draft')
  end

  # Called by the bot once Discord has accepted the message.
  def mark_posted!(message_id, body:)
    transaction do
      update!(status: 'posted', discord_message_id: message_id, rendered_body: body,
              posted_at: Time.zone.now, last_error: nil)
      # Stamped here so a reaction lookup is one indexed hit with no join.
      options.update_all(discord_message_id: message_id, updated_at: Time.zone.now)
    end
  end

  def mark_failed!(error)
    update!(status: 'failed', last_error: error.to_s.first(255))
  end

  def close!
    update!(status: 'closed', closed_at: Time.zone.now)
  end

  def reopen!
    return false unless status == 'closed'

    update!(status: 'posted', closed_at: nil)
  end

  # Back to an editable draft, with every trace of the message that was sent.
  #
  # Called by the bot AFTER the message is confirmed gone, never before — see
  # the migration for why that ordering is the whole design.
  #
  # The options' discord_message_id has to go too. It is the key every reaction
  # lookup uses (`SignupOption.for_reaction`), so leaving it would point the
  # next reaction at a message that no longer exists.
  def revoke!
    transaction do
      update!(status: 'draft', discord_message_id: nil, posted_at: nil,
              rendered_body: nil, closed_at: nil, revoke_requested_at: nil,
              last_error: nil)
      options.update_all(discord_message_id: nil, updated_at: Time.zone.now)
    end
  end

  def revoking?
    revoke_requested_at.present?
  end

  # How many people would lose their sign-up if this were revoked now. Named in
  # the confirmation, because "3 people have reacted" is the fact that decides
  # whether you press it.
  def live_reaction_count
    SignupReaction.live.where(signup_option_id: options.select(:id)).count
  end

  def message_link
    return nil if discord_message_id.nil? || channel&.server.nil?

    "https://discord.com/channels/#{channel.server.discord_id}/#{channel.discord_id}/#{discord_message_id}"
  end

  def reaction_count
    options.sum(&:live_reaction_count)
  end

  def summary
    return 'No options yet' if options.empty?

    "#{options.size} #{'option'.pluralize(options.size)}"
  end

  private

  def post_at_required_when_scheduled
    return unless status == 'scheduled' && post_at.blank?

    errors.add(:post_at, 'is needed before a post can be scheduled')
  end
end
