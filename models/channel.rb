class Channel < ApplicationRecord
  belongs_to :server
  has_many :events

  # A job a channel does for the bot, set with `rake snipes:channel[ID]`.
  #
  # A column rather than the name, because Bot::Setup#setup_channels rewrites
  # `name` from Discord on every boot — renaming the channel in Discord must
  # not silently switch enforcement off. One channel per purpose, held by the
  # partial unique index.
  PURPOSES = %w[snipes].freeze
  validates :purpose, inclusion: { in: PURPOSES }, allow_nil: true

  scope :notice_requested, -> { where.not(notice_requested_at: nil) }
  # Where rides may go: every channel without a job of its own. The snipes
  # channel sits in this table too, and a sign-up — @Riders ping and all —
  # posted there by one wrong pick in a dropdown is not undone by deleting it.
  scope :for_rides, -> { where(purpose: nil) }

  def self.snipes = find_by(purpose: 'snipes')

  # Make this the one channel with the given purpose. A channel the bot has
  # never been told about is created under the single server, so switching to
  # a brand-new snipes channel is one command rather than config.yml plus a
  # seed run — Setup#setup_channels fills in its real name on the next boot.
  def self.assign_purpose!(purpose, discord_id:)
    raise ArgumentError, "unknown purpose #{purpose.inspect}" unless PURPOSES.include?(purpose)

    transaction do
      where(purpose: purpose).where.not(discord_id: discord_id).update_all(purpose: nil)
      channel = find_or_initialize_by(discord_id: discord_id) do |c|
        c.server = Server.first or raise 'no server row yet — run the bot once'
        c.name = purpose
      end
      channel.update!(purpose: purpose)
      channel
    end
  end
end
