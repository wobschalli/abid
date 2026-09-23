require 'digest'
require 'json'

# Fingerprints what a driver needs to know, so "changed since last sent" is a
# comparison rather than a guess.
#
# Deliberately excludes the route, the maps URL, phone formatting and the body
# text. Those are derived; if they were included, a re-render would look like a
# change and every driver would be permanently marked "changed" — at which
# point the feature is noise and nobody reads it.
module DispatchDigest
  module_function

  def canonical(driver_ride, riders, event)
    {
      e: [event.id, event.start_time&.iso8601, event.location_id],
      d: [driver_ride.user_id, driver_ride.capacity, driver_ride.status,
          driver_ride.pickup_location_id, driver_ride.pickup_address.to_s],
      # Sorted: a set of riders, not an order. Reordering pickups is not a
      # change the driver needs re-telling about.
      r: riders.map do |rider|
        [rider.user_id, rider.status, rider.pickup_location_id,
         rider.pickup_address.to_s, rider.note.to_s]
      end.sort
    }
  end

  def for(driver_ride, riders, event)
    Digest::SHA256.hexdigest(JSON.generate(canonical(driver_ride, riders, event)))
  end
end
