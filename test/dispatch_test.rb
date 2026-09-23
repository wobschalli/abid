require_relative 'test_helper'
# The sender resolves Discordrb::Webhooks::View lazily so the web process need
# not load discordrb — but without it here the button path would never run and
# every test would silently exercise the plain-DM fallback instead.
require 'discordrb'

class DispatchTest < AbidTest
  class FakeDM
    def id = 4242
  end

  # The DM channel. `User#pm` with no argument returns it, which is what the
  # components-aware send needs — `User#dm(body)` cannot carry a button.
  class FakeChannel
    def id = 99_001
  end

  class FakeDiscordUser
    attr_reader :dms

    def initialize(raise_with: nil, no_pm: false)
      @raise_with = raise_with
      @no_pm = no_pm
      @dms = []
    end

    # Standing in for an older discordrb, to exercise the fallback.
    def pm
      raise NoMethodError, "undefined method `pm'" if @no_pm
      # Opening a DM channel with someone who has them closed fails here, not
      # at send — which is why this must raise before a channel exists.
      raise @raise_with if @raise_with

      FakeChannel.new
    end

    def dm(body)
      raise @raise_with if @raise_with

      @dms << body
      FakeDM.new
    end
  end

  class FakeBot
    attr_reader :users, :components

    def initialize(raise_with: nil, no_pm: false)
      @raise_with = raise_with
      @no_pm = no_pm
      @components = []
      @users = Hash.new { |h, k| h[k] = FakeDiscordUser.new(raise_with: @raise_with, no_pm: @no_pm) }
    end

    def user(discord_id) = @users[discord_id]

    # The patched Discordrb::Bot#send, which is what carries components.
    def send(_channel_id, body, components: nil, **_opts)
      raise @raise_with if @raise_with

      @components << components
      @bodies ||= []
      @bodies << body
      FakeDM.new
    end

    def sent_bodies = (@bodies || []) + @users.values.flat_map(&:dms)
  end

  def setup
    super
    @event = make_event(name: 'Sunday School')
    # A destination is what makes a directions link possible; without one the
    # planner correctly produces no URL.
    @event.update!(location: location_in(ZONE_1))
    @driver = make_driver(@event, 'ian', seats: 4, zone: ZONE_1)
    @rider = make_rider(@event, 'caitlin', zone: ZONE_1, driver: @driver)
    @rider.update!(pickup_address: 'Harker Hall lot')
    @rider.user.update!(phone: '(765) 555-0134')
  end

  def board = RideBoard.new(@event.reload)

  def plan(scope: 'all')
    DispatchPlanner.new(board, requested_by: nil, scope: scope).call
  end

  # --- planning ------------------------------------------------------------

  def test_planning_creates_one_message_per_car
    dispatch = plan

    assert_equal 1, dispatch.messages.count
    message = dispatch.messages.first
    assert_equal 'pending', message.status
    assert_equal 'ian', message.driver_name
    assert_equal ['caitlin'], message.rider_names
  end

  def test_the_roster_snapshot_captures_what_the_driver_needs
    roster = plan.messages.first.roster

    assert_equal 'Sunday School', roster.dig('event', 'name')
    rider = roster['riders'].first
    assert_equal 'caitlin', rider['name']
    assert_equal 'Harker Hall lot', rider['pickup']
    assert_equal '(765) 555-0134', rider['phone']
    assert_includes roster['maps_url'].to_s, 'google.com/maps/dir/'
  end

  def test_attempts_increment
    plan
    second = plan

    assert_equal 2, second.attempt
  end

  # A driver with no changes is still recorded, so an attempt is a complete
  # picture of the board at that moment.
  def test_changed_scope_skips_drivers_that_are_up_to_date
    first = plan(scope: 'all')
    deliver(first)

    second = DispatchPlanner.new(board, scope: 'changed').call
    assert_nil second, 'nothing changed, so there should be nothing to send'
  end

  def test_changed_scope_picks_up_a_driver_whose_car_changed
    deliver(plan(scope: 'all'))

    make_rider(@event, 'jalen', zone: ZONE_1, driver: @driver).update!(pickup_address: 'Eastgate')

    dispatch = DispatchPlanner.new(board, scope: 'changed').call
    refute_nil dispatch
    assert_equal 1, dispatch.messages.pending.count
  end

  # --- digest --------------------------------------------------------------

  # A digest that flaps marks every driver "changed" forever and the feature
  # becomes noise nobody reads.
  def test_the_digest_is_stable_across_recomputation
    a = DispatchDigest.for(@driver, [@rider], @event)
    b = DispatchDigest.for(@driver.reload, [@rider.reload], @event.reload)

    assert_equal a, b
  end

  def test_the_digest_ignores_rider_order
    other = make_rider(@event, 'jalen', zone: ZONE_1, driver: @driver)
    a = DispatchDigest.for(@driver, [@rider, other], @event)
    b = DispatchDigest.for(@driver, [other, @rider], @event)

    assert_equal a, b
  end

  def test_the_digest_changes_when_a_rider_is_added
    before = DispatchDigest.for(@driver, [@rider], @event)
    other = make_rider(@event, 'jalen', zone: ZONE_1, driver: @driver)

    refute_equal before, DispatchDigest.for(@driver, [@rider, other], @event)
  end

  def test_the_digest_changes_when_a_pickup_changes
    before = DispatchDigest.for(@driver, [@rider], @event)
    @rider.update!(pickup_address: 'somewhere else')

    refute_equal before, DispatchDigest.for(@driver, [@rider.reload], @event)
  end

  # Moving one rider must mark BOTH the old and the new driver as changed.
  def test_moving_a_rider_changes_both_drivers
    other_driver = make_driver(@event, 'caleb', seats: 4, zone: ZONE_3)
    deliver(plan(scope: 'all'))

    @rider.update!(driver_ride_id: other_driver.id)

    states = DispatchStatus.new(board).states
    assert_equal :changed, states[@driver.id]
    assert_equal :changed, states[other_driver.id]
  end

  # --- sending -------------------------------------------------------------

  def test_the_bot_dms_each_driver_and_records_it
    dispatch = plan
    bot = FakeBot.new
    DispatchSender.new(bot).pump

    message = dispatch.messages.first.reload
    assert_equal 'sent', message.status
    assert_equal 'sent', dispatch.reload.status
    refute_nil message.sent_at
    assert_equal 1, bot.sent_bodies.size
    assert_includes bot.sent_bodies.first, 'Caitlin'
    assert_includes bot.sent_bodies.first, 'Harker Hall lot'
    assert_includes bot.sent_bodies.first, '(765) 555-0134'
  end

  def test_a_closed_dm_is_recorded_not_raised
    dispatch = plan
    bot = FakeBot.new(raise_with: RuntimeError.new('Cannot send messages to this user'))

    DispatchSender.new(bot).pump

    message = dispatch.messages.first.reload
    assert_equal 'failed', message.status
    assert_includes message.error_message, 'Cannot send messages'
    assert_equal 'failed', dispatch.reload.status
  end

  def test_a_partial_failure_is_marked_partial
    make_driver(@event, 'caleb', seats: 4, zone: ZONE_3)
    dispatch = plan
    bot = FakeBot.new
    # One driver's DMs are closed.
    bot.users[@driver.user.discord_id] # instantiate the good one
    failing = dispatch.messages.find { |m| m.driver_name == 'caleb' }
    failing.update!(discord_id: 999_999)
    bot.instance_variable_get(:@users)[999_999] =
      FakeDiscordUser.new(raise_with: RuntimeError.new('closed'))

    DispatchSender.new(bot).pump

    assert_equal 'partial', dispatch.reload.status
    assert_equal 1, dispatch.messages.sent.count
    assert_equal 1, dispatch.messages.failed.count
  end

  def test_pumping_twice_does_not_dm_twice
    plan
    bot = FakeBot.new

    DispatchSender.new(bot).pump
    DispatchSender.new(bot).pump

    assert_equal 1, bot.sent_bodies.size
  end

  def test_a_stalled_dispatch_is_requeued
    dispatch = plan
    dispatch.update!(status: 'sending', started_at: 20.minutes.ago)

    Dispatch.reap_stalled!
    assert_equal 'queued', dispatch.reload.status
  end

  def test_an_event_with_dispatches_cannot_be_destroyed
    plan

    refute @event.destroy
    assert Event.exists?(@event.id), 'dispatch history was destroyed with the event'
  end

  # Pressing send produced no visible change for up to thirty seconds, because
  # a message waiting in the outbox was indistinguishable from one never sent.
  def test_a_queued_message_reads_as_queued_not_unsent
    event = make_event
    driver = make_driver(event, 'caleb', seats: 4)
    board = RideBoard.new(event)

    assert_equal :never, DispatchStatus.new(board).state_for(driver)

    DispatchPlanner.new(board, requested_by: nil, scope: 'all').call

    status = DispatchStatus.new(RideBoard.new(event))
    assert_equal :queued, status.state_for(driver)
    assert_equal 1, status.queued_count
    refute_includes status.stale_driver_rides, driver,
                    'a driver already queued must not be counted as still needing a message'
  end

  # --- "Got it" ------------------------------------------------------------
  #
  # Discord tells a bot nothing about whether a DM was read, so the driver says
  # so themselves.

  def test_the_dm_carries_a_got_it_button
    plan
    bot = FakeBot.new
    DispatchSender.new(bot).pump

    view = bot.components.compact.first
    refute_nil view, 'the DM should have been sent with components'

    button = view.to_a.dig(0, :components, 0)
    assert_equal 'Got it', button[:label]
    assert_match(/\Adispatch_ack_\d+\z/, button[:custom_id],
                 'the handler matches on the message id in the custom_id')
  end

  # A driver getting their roster without a button beats not getting it at all.
  def test_it_falls_back_to_a_plain_dm_when_the_button_cannot_be_attached
    plan
    bot = FakeBot.new(no_pm: true)

    capture_io { DispatchSender.new(bot).pump }

    assert_equal 'sent', DispatchMessage.last.status
    refute_empty bot.sent_bodies
    assert_empty bot.components.compact
  end

  def test_a_delivered_message_starts_unconfirmed
    event = make_event
    driver = make_driver(event, 'caleb', seats: 4)
    deliver(DispatchPlanner.new(RideBoard.new(event), requested_by: nil, scope: 'all').call)

    message = DispatchMessage.last
    assert message.sent?
    refute message.acknowledged?
    assert_equal :sent, DispatchStatus.new(RideBoard.new(event)).state_for(driver)
  end

  def test_pressing_got_it_confirms_it
    event = make_event
    driver = make_driver(event, 'caleb', seats: 4)
    deliver(DispatchPlanner.new(RideBoard.new(event), requested_by: nil, scope: 'all').call)

    assert DispatchMessage.last.acknowledge!

    status = DispatchStatus.new(RideBoard.new(event))
    assert_equal :confirmed, status.state_for(driver)
    assert_equal 1, status.confirmed_count
    assert_equal 0, status.awaiting_count
    refute_includes status.stale_driver_rides, driver, 'a confirmed driver needs no re-send'
  end

  # Discord will deliver a second press if the driver taps twice; it must not
  # move the timestamp or raise.
  def test_pressing_it_twice_changes_nothing
    event = make_event
    make_driver(event, 'caleb', seats: 4)
    deliver(DispatchPlanner.new(RideBoard.new(event), requested_by: nil, scope: 'all').call)

    message = DispatchMessage.last
    message.acknowledge!
    first = message.acknowledged_at

    refute message.acknowledge!
    assert_equal first, message.reload.acknowledged_at
  end

  def test_an_unsent_message_cannot_be_confirmed
    event = make_event
    make_driver(event, 'caleb', seats: 4)
    DispatchPlanner.new(RideBoard.new(event), requested_by: nil, scope: 'all').call

    message = DispatchMessage.last
    refute message.sent?
    refute message.acknowledge!
  end

  # What they confirmed is out of date the moment the car changes, so a moved
  # rider must put the driver back in the queue even though they pressed it.
  def test_a_roster_change_outranks_an_earlier_confirmation
    event = make_event
    driver = make_driver(event, 'caleb', seats: 4)
    deliver(DispatchPlanner.new(RideBoard.new(event), requested_by: nil, scope: 'all').call)
    DispatchMessage.last.acknowledge!

    rider = make_rider(event, 'nathan')
    rider.update!(driver_ride: driver)

    status = DispatchStatus.new(RideBoard.new(event))
    assert_equal :changed, status.state_for(driver)
    assert_includes status.stale_driver_rides, driver
  end

  private

  def deliver(dispatch)
    DispatchSender.new(FakeBot.new).pump
    dispatch.reload
  end


end
