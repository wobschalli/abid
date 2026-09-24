module Snipes
  # One person's answer to "may we snipe you?", from a button press.
  #
  # The default is yes — that is how the channel has always worked — so only
  # an explicit opt-out is stored as true. Goes through DiscordUserSync so a
  # press from someone the bot has never seen (in the server before the bot
  # was, never reacted to anything) creates their row rather than failing:
  # every other button handler here assumes a User exists, and that is a
  # NoMethodError waiting for the first stranger who clicks.
  class Preference
    Result = Struct.new(:user, :opt_out, :changed, keyword_init: true)

    def self.set(discord_id:, opt_out:, username: nil, display_name: nil)
      user = DiscordUserSync.upsert!(discord_id: discord_id, username: username, display_name: display_name)
      changed = user.snipes_opt_out != opt_out
      user.update!(snipes_opt_out: opt_out, snipes_preference_at: Time.zone.now) if changed
      Result.new(user: user, opt_out: opt_out, changed: changed)
    end

    # /toggle-sniping: flip whatever the current answer is. Default is
    # snipable, so a first press opts out; a second puts them back in.
    def self.toggle(discord_id:, username: nil, display_name: nil)
      user = DiscordUserSync.upsert!(discord_id: discord_id, username: username, display_name: display_name)
      set(discord_id: discord_id, opt_out: !user.snipes_opt_out, username: username, display_name: display_name)
    end

    # What the presser sees, privately. The shared message never changes.
    def self.reply_for(opt_out)
      if opt_out
        "Got it, you're out. Any snipe that tags you will get taken down."
      else
        "You're back in 📸"
      end
    end
  end
end
