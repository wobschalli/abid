# Removes everything `rake db:demo` invented, leaving the real server's data
# alone. Run it once the bot has synced real members and you want the ride board
# to show only real people:
#
#   rake db:drop_demo          # report what it would remove
#   rake db:drop_demo[apply]   # remove it
#
# Demo rows are identified by their Discord snowflake. Real ids are ~18-19
# digits (1.1e18); the demo seeds use small made-up numbers in the 9e8 range, so
# a single threshold separates them cleanly and there is no guessing by name.
module Abid
  module DropDemo
    # Anything below this is invented. A real Discord snowflake has not been
    # this small since 2015.
    REAL_ID_FLOOR = 1_000_000_000_000

    module_function

    def call(apply: false)
      counts = {}

      ActiveRecord::Base.transaction do
        users    = User.where('discord_id < ?', REAL_ID_FLOOR)
        channels = Channel.where('discord_id < ?', REAL_ID_FLOOR)
        servers  = Server.where('discord_id < ?', REAL_ID_FLOOR)
        posts    = SignupPost.where(channel: channels)
        rides    = Ride.where(user: users)

        counts['demo members']   = users.count
        counts['their rides']    = rides.count
        counts['demo channels']  = channels.count
        counts['demo servers']   = servers.count
        counts['sign-up posts']  = posts.count
        counts['dispatches']     = Dispatch.count
        counts['clashes']        = Clash.where(user: users).count

        if apply
          # The dispatch log only ever described the demo board.
          DispatchMessage.delete_all
          Dispatch.delete_all

          # Clash has no dependent: :destroy from User, so it would block the
          # delete rather than follow it.
          Clash.where(user: users).delete_all

          # destroy_all, not delete_all: options and their reactions cascade.
          posts.destroy_all

          # `ride_id` is optional on a reaction but the FK is still enforced, so
          # a surviving real reaction pointing at a demo ride has to let go of
          # it first.
          counts['reactions detached from demo rides'] =
            SignupReaction.where(ride_id: rides.select(:id)).update_all(ride_id: nil)

          # A real post composed while signed in as a demo account. created_by
          # is an audit note and optional — the post keeps everything that
          # matters and simply loses its author.
          counts['posts that lose a demo author'] =
            SignupPost.where(created_by_id: users.select(:id)).update_all(created_by_id: nil)

          # driver_ride_id is a self-reference: break it first or a passenger
          # row blocks the deletion of its own driver.
          rides.update_all(driver_ride_id: nil)
          rides.delete_all

          users.delete_all
          channels.delete_all
          servers.delete_all
        end
      end

      report(counts, apply: apply)
      counts
    end

    def report(counts, apply:)
      puts(apply ? '== removed ==' : '== DRY RUN — nothing removed ==')
      counts.each { |label, n| puts "  #{n.to_s.rjust(4)}  #{label}" }
      puts
      puts "kept: #{User.count} members, #{Event.count} events, " \
           "#{Location.count} locations, #{SignupPost.count} sign-up posts"
    end
  end
end
