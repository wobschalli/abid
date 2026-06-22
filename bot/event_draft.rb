require 'securerandom'
require 'monitor'

# In-memory ephemeral store for events being built through the interactive dashboard.
# Drafts are NOT persisted to the database until the user clicks Publish or Save as Unpublished.
class EventDraft
  @store = {}
  @mutex = Monitor.new

  class << self
    attr_reader :store, :mutex

    # Create a new draft for building a brand-new event.
    def create(attrs = {})
      mutex.synchronize do
        draft = new(attrs)
        store[draft.id] = draft
        draft
      end
    end

    # Find any draft by its ephemeral id.
    def find(id)
      mutex.synchronize { store[id] }
    end

    # Delete a draft by id.
    def delete(id)
      mutex.synchronize { store.delete(id) }
    end

    # Return a canonical editable draft for an existing persisted event.
    # Re-uses the existing in-memory draft if one is already bound to this event,
    # preventing stale duplicates when the user re-opens the dashboard.
    def for_event(event, organizer_id: nil)
      mutex.synchronize do
        existing = store.values.find { |d| d.event_id == event.id }
        return existing if existing

        create(
          event_id: event.id,
          organizer_id: organizer_id || event.organizer_id,
          name: event.name,
          location: event.location,
          channel: event.channel,
          start_time: event.start_time,
          end_time: event.end_time,
          message_rides_at: event.message_rides_at,
          collect_rides_at: event.collect_rides_at,
          repeats_every: event.repeats_every,
          message: event.message,
          emojis: event.emojis.to_a,
          status: event.status
        )
      end
    end
  end

  attr_accessor :id, :event_id, :organizer_id, :name, :location, :channel,
                :start_time, :end_time, :message_rides_at, :collect_rides_at,
                :repeats_every, :message, :emojis, :status

  def initialize(attrs = {})
    @id = SecureRandom.hex(4)
    @event_id = attrs[:event_id]
    @organizer_id = attrs[:organizer_id]
    @name = attrs[:name]
    @location = attrs[:location]
    @channel = attrs[:channel]
    @start_time = attrs[:start_time]
    @end_time = attrs[:end_time]
    @message_rides_at = attrs[:message_rides_at]
    @collect_rides_at = attrs[:collect_rides_at]
    @repeats_every = attrs[:repeats_every] || 'never'
    @message = attrs[:message]
    @emojis = attrs[:emojis] || []
    @status = attrs[:status] || :draft_in_memory
  end

  def persisted?
    !@event_id.nil?
  end

  def ready_to_publish?
    name.present? && location && channel &&
      start_time && end_time && message_rides_at && collect_rides_at &&
      message.present? && emojis.any?
  end

  def ready_to_save?
    name.present?
  end

  def repeats_every
    @repeats_every || 'never'
  end

  def organization_valid?
    return true unless [start_time, end_time, message_rides_at, collect_rides_at].all?

    message_rides_at < start_time &&
      collect_rides_at >= message_rides_at &&
      collect_rides_at <= end_time &&
      end_time > start_time
  end

  def validation_errors
    errors = []
    errors << 'A name is required.' unless name.present?
    errors << 'A location is required.' unless location
    errors << 'A channel is required.' unless channel
    errors << 'Start time, end time, message time, and collect time are all required.' unless [start_time, end_time, message_rides_at, collect_rides_at].all?
    errors << 'Message time must be before start time.' if message_rides_at && start_time && message_rides_at >= start_time
    errors << 'Collect time must be between message time and event end.' if [message_rides_at, collect_rides_at, end_time].all? && (collect_rides_at < message_rides_at || collect_rides_at > end_time)
    errors << 'Event end must be after start time.' if start_time && end_time && end_time <= start_time
    errors << 'At least one reaction emoji is required.' unless emojis.any?
    errors << 'A message is required.' unless message.present?
    errors
  end

  def to_event_attributes
    {
      name: name,
      organizer_id: organizer_id,
      location: location,
      channel: channel,
      start_time: start_time,
      end_time: end_time,
      message_rides_at: message_rides_at,
      collect_rides_at: collect_rides_at,
      repeats_every: repeats_every,
      message: message
    }
  end
end
