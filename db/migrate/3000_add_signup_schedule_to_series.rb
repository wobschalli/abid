# Lets recurrence reach all the way to the Discord message.
#
# EventSeries -> Event was already automatic. Event -> SignupPost was a weekly
# hand-click: create the post, type a send time, press Save, press Schedule,
# retype the footer. Every one of those answers is the same every week, so it
# belongs on the template rather than in someone's fingers.
#
# `signup_lead_days` + `signup_post_time` say "3 days before at 8:00 PM", which
# is Thursday 8pm for a Sunday service and Tuesday 8pm for Friday Abide. Stored
# as an offset rather than a weekday so a series that moves keeps its habit.
class AddSignupScheduleToSeries < ActiveRecord::Migration[8.0]
  def change
    add_column :event_series, :signup_lead_days, :integer, default: 3, null: false
    add_column :event_series, :signup_post_time, :time, default: '20:00', null: false
    # The "React by 8am Sunday" line, which had nowhere to live and was retyped
    # on every post or forgotten.
    add_column :event_series, :signup_outro, :string
  end
end
