# A vehicle riders walk TO, instead of one that drives to them.
#
# The church van sits in the Windsor parking lot and leaves for the service;
# nobody expects a 12-seat van to snake through campus. Modelling it as an
# ordinary car gave the optimizer a huge cheap vehicle and produced exactly
# that snake.
#
# On the ride, not the user: whether a given car is a meeting point is a fact
# about tonight's vehicle, and the same person may drive their own car next
# week. Lives on the driver's ride row; meaningless on riders.
class AddMeetAtPickupToRides < ActiveRecord::Migration[8.0]
  def change
    add_column :rides, :meet_at_pickup, :boolean, default: false, null: false
  end
end
