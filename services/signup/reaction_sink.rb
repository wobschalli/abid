module Signup
  # Turns reactions into rides.
  #
  # Every edge case lives here rather than in the discordrb handlers, so the
  # whole thing is testable with plain ActiveRecord and no Discord at all. The
  # handlers are three lines each.
  #
  # The governing rule: this class only ever mutates rides it created
  # (`source: 'discord'`). A rider a coordinator added by hand is never removed,
  # never re-roled, and never cancelled by Discord traffic.
  class ReactionSink
    Result = Struct.new(:status, :option, :ride, keyword_init: true)

    # :ignored      not our message, not our emoji, or not our ride
    # :created      new ride
    # :reactivated  they had dropped out and came back
    # :duplicate    already recorded; Discord redelivers on gateway resume
    # :closed       post is closed; recorded but no ride
    # :unbound      emoji has no occurrence bound yet; recorded but no ride
    # :cancelled    un-reacted before being seated; ride removed
    # :dropped      un-reacted after being seated; seat freed, row kept
    def add(message_id:, emoji_key:, discord_user_id:, username: nil,
            display_name: nil, bot: false, at: nil, source: 'gateway')
      at ||= Time.zone.now
      return ignored if bot
      return ignored if emoji_key.blank?

      option = SignupOption.for_reaction(message_id, emoji_key)
      return ignored if option.nil?

      SignupOption.transaction do
        post = option.signup_post
        user = DiscordUserSync.upsert!(discord_id: discord_user_id, username: username,
                                       display_name: display_name)
        reaction = record_reaction(option, discord_user_id, user, at, source)

        # Recorded either way, so a coordinator can see who tried after close,
        # and so binding an option later can backfill everyone who reacted early.
        return Result.new(status: :closed, option: option) unless post.open?
        return Result.new(status: :unbound, option: option) if option.event_id.nil?

        attach_ride(option, user, reaction, at)
      end
    end

    def remove(message_id:, emoji_key:, discord_user_id:, at: nil, source: 'gateway')
      at ||= Time.zone.now
      option = SignupOption.for_reaction(message_id, emoji_key)
      return ignored if option.nil?

      SignupOption.transaction do
        reaction = option.signup_reactions.find_by(discord_user_id: discord_user_id)
        return ignored if reaction.nil? || reaction.removed_at.present?

        reaction.update!(removed_at: at, source: source)
        detach_ride(reaction, option, at)
      end
    end

    # Someone cleared every reaction on the message.
    def remove_all(message_id:, at: nil)
      at ||= Time.zone.now
      options = SignupOption.where(discord_message_id: message_id).to_a
      return [] if options.empty?

      options.flat_map do |option|
        option.signup_reactions.live.pluck(:discord_user_id).map do |discord_user_id|
          remove(message_id: message_id, emoji_key: option.emoji_key,
                 discord_user_id: discord_user_id, at: at, source: 'reconcile')
        end
      end
    end

    private

    def ignored
      Result.new(status: :ignored)
    end

    def record_reaction(option, discord_user_id, user, at, source)
      reaction = option.signup_reactions.find_or_initialize_by(discord_user_id: discord_user_id)
      reaction.user = user
      reaction.source = source
      reaction.reacted_at ||= at
      # Re-reacting after removing clears the tombstone.
      reaction.removed_at = nil
      reaction.save!
      reaction
    end

    def attach_ride(option, user, reaction, at)
      ride = option.event.rides.find_or_initialize_by(user_id: user.id)

      if ride.new_record?
        ride.assign_attributes(
          role: 'rider', status: 'requested', source: 'discord',
          zone: user.location&.zone, signed_up_at: at
        )
        ride.save!
        reaction.update!(ride: ride)
        return Result.new(status: :created, option: option, ride: ride)
      end

      # A coordinator's row, or a driver — link the reaction, change nothing.
      unless ride.from_discord? && ride.rider?
        reaction.update!(ride: ride)
        return Result.new(status: :ignored, option: option, ride: ride)
      end

      reaction.update!(ride: ride)
      return Result.new(status: :duplicate, option: option, ride: ride) unless ride.out?

      # They had dropped out and came back.
      ride.update!(status: ride.driver_ride_id ? 'assigned' : 'requested', dropped_at: nil)
      Result.new(status: :reactivated, option: option, ride: ride)
    rescue ActiveRecord::RecordNotUnique
      # Gateway and reconciler racing on the same person.
      ride = option.event.rides.find_by(user_id: user.id)
      reaction.update!(ride: ride) if ride
      Result.new(status: :duplicate, option: option, ride: ride)
    end

    def detach_ride(reaction, option, at)
      ride = reaction.ride
      return Result.new(status: :ignored, option: option) if ride.nil?

      # Never touch a coordinator's row, and never delete a driver — that would
      # silently empty a car someone has already planned around.
      return Result.new(status: :ignored, option: option, ride: ride) unless ride.from_discord?
      return Result.new(status: :ignored, option: option, ride: ride) if ride.driver?

      # Two options can point at the same occurrence ("either time works"). The
      # ride survives until the last live reaction backing it is gone.
      still_backed = SignupReaction.live
                                   .where(ride_id: ride.id)
                                   .where.not(id: reaction.id)
                                   .exists?
      return Result.new(status: :ignored, option: option, ride: ride) if still_backed

      if ride.driver_ride_id.nil?
        ride.destroy!
        Result.new(status: :cancelled, option: option)
      else
        # Seated already: free the seat, keep the row visible. Decided with the
        # coordinator — a mis-tap must not silently empty a planned car.
        ride.update!(status: 'no_show', driver_ride_id: nil, dropped_at: at)
        Result.new(status: :dropped, option: option, ride: ride)
      end
    end
  end
end
