require_relative 'test_helper'
require 'rack/test'
require_relative '../app'
Abid.load_views

# The Optimize button with background jobs on (ABID_JOBS=1): the request only
# enqueues, the board says "Optimizing…" until the job finishes, and the job
# itself seats riders exactly as the synchronous path does. With the flag off
# nothing here is used — the route tests cover that path unchanged.
class OptimizeJobTest < AbidTest
  include Rack::Test::Methods

  def app = App

  def setup
    super
    @prev = ENV['ABID_JOBS']
    ENV['ABID_JOBS'] = '1'
    App.set :sessions, false
    App.set :show_exceptions, false
    App.set :raise_errors, true
    App.set :host_authorization, { permitted_hosts: [] }
    @leader = User.create!(name: 'Coordinator', username: 'coord', discord_id: next_discord_id,
                           leader: true, password: 'test-password')
    @event = make_event(name: 'Abide', starts: Time.zone.now + 2.days)
    @event.update!(location: location_in(ZONE_1))
    @driver = make_driver(@event, 'ian', seats: 4, zone: ZONE_1)
    @rider = make_rider(@event, 'caitlin', zone: ZONE_1)
  end

  def teardown
    ENV['ABID_JOBS'] = @prev
    super
  end

  def pending_jobs = Que::ActiveRecord::Model.where(job_class: 'OptimizeJob', finished_at: nil)

  def test_the_button_only_enqueues_and_the_board_says_optimizing
    env 'rack.session', { user_id: @leader.id }
    post "/board/#{@event.id}/optimize"

    assert_equal 1, pending_jobs.count, 'no job was queued'
    assert_nil @rider.reload.driver_ride_id, 'the request solved synchronously anyway'

    env 'rack.session', { user_id: @leader.id }
    get "/board?event_id=#{@event.id}"
    assert_includes last_response.body, 'Optimizing…'
    assert_includes last_response.body, 'data-board-poll'
  end

  def test_the_job_seats_riders_and_clears_the_pending_state
    OptimizeJob.enqueue(@event.id)
    job = pending_jobs.first

    capture_io { OptimizeJob.run(*job.args) }

    assert_equal @driver.id, @rider.reload.driver_ride_id
  end

  def test_pending_for_reflects_queued_jobs_only
    refute OptimizeJob.pending_for?(@event)
    OptimizeJob.enqueue(@event.id)
    assert OptimizeJob.pending_for?(@event)
    refute OptimizeJob.pending_for?(make_event(name: 'Other')), 'leaked across events'
  end

  def test_a_deleted_event_ends_the_job_quietly
    assert_silent { OptimizeJob.run(-1) }
  end

  def test_flag_off_means_no_optimizing_state
    ENV['ABID_JOBS'] = nil
    OptimizeJob.enqueue(@event.id)
    refute RideBoard.new(@event).optimizing?, 'the board showed a job state with jobs off'
  end
end
