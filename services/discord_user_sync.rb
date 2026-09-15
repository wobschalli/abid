# Find or create the User behind a Discord id.
#
# Extracted from Messenger#handle_member_join, which was the only place that
# knew a User needs a generated password (has_secure_password) and that `leader`
# comes from the Leaders/Coordinator roles. The reaction sink needs the same
# logic for someone who reacts without ever having triggered a join event —
# anyone who was already in the server when the bot was added.
class DiscordUserSync
  LEADER_ROLES = ['Leaders', 'Coordinator'].freeze

  def self.upsert!(discord_id:, username: nil, display_name: nil, leader: nil)
    new(discord_id: discord_id, username: username, display_name: display_name, leader: leader).upsert!
  end

  def initialize(discord_id:, username: nil, display_name: nil, leader: nil)
    @discord_id = discord_id.to_i
    @username = username
    @display_name = display_name
    @leader = leader
  end

  def upsert!
    user = User.find_by(discord_id: @discord_id)
    return backfill(user) if user

    create
  rescue ActiveRecord::RecordNotUnique
    # Gateway event and reconciliation sweep can race on the same person.
    User.find_by(discord_id: @discord_id)
  end

  private

  # Never overwrite a name someone has curated on the dashboard; only fill gaps.
  def backfill(user)
    changes = {}
    changes[:username] = @username if user.username.blank? && @username.present?
    changes[:name] = @display_name if user.name.blank? && @display_name.present?
    changes[:leader] = true if @leader && !user.leader
    user.update(changes) if changes.any?
    user
  end

  def create
    password = Abid.passgen
    User.create!(
      discord_id: @discord_id,
      username: @username.presence || "user#{@discord_id}",
      name: @display_name.presence || @username,
      leader: @leader.present?,
      password: password,
      password_confirmation: password
    )
  end
end
