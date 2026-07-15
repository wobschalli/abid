module DraftHelper

  private

  # ---------------------------------------------------------------------------
  # Permission / draft helpers
  # ---------------------------------------------------------------------------

  def with_draft(event)
    draft_id = event.custom_id.to_s.split('_').last
    draft = EventDraft.find(draft_id)
    return event.respond(content: 'This draft has expired or was already saved.', ephemeral: true) unless draft

    user = User.find_by(discord_id: event.user.id)
    return event.respond(content: 'You don\'t have permission to do this!', ephemeral: true) unless user&.leader || user&.coordinator? || draft.organizer_id == user&.id

    yield draft
  end

  def with_event(event)
    event_id = event.custom_id.to_s.match(/_(\d+)$/)&.[](1).to_i
    evt = Event.find_by(id: event_id)
    return event.respond(content: 'Event not found.', ephemeral: true) unless evt

    user = User.find_by(discord_id: event.user.id)
    return event.respond(content: 'You don\'t have permission to do this!', ephemeral: true) unless user&.leader || user&.coordinator? || evt.organizer_id == user&.id

    yield evt
  end

  def with_draft_or_event(event)
    identifier = event.custom_id.to_s.split('_').last
    if identifier.to_s.match?(/\A[0-9a-f]{8}\z/i)
      with_draft(event) { |draft| yield draft }
    else
      with_event(event) do |evt|
        draft = EventDraft.for_event(evt, organizer_id: evt&.organizer_id)
        yield draft
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Publish / save / discard
  # ---------------------------------------------------------------------------

  def publish_draft(event, draft)
    unless draft.ready_to_publish?
      return event.respond(content: 'This event is missing required information before it can be published.', ephemeral: true)
    end

    time_errors = draft.validation_errors
    return event.respond(content: "Cannot publish:\n#{time_errors.join("\n")}", ephemeral: true) if time_errors.any?

    event.defer_update
    evt = persist_draft(draft, status: :scheduled)
    bot_schedule(evt)
    EventDraft.delete(draft.id)

    event.edit_response content: "🚀 Event **#{evt.name}** published and scheduled!", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def save_draft_as_unpublished(event, draft)
    unless draft.ready_to_save?
      return event.respond(content: 'An event name is required to save.', ephemeral: true)
    end

    event.defer_update
    evt = persist_draft(draft, status: :unpublished)
    EventDraft.delete(draft.id)

    event.edit_response content: "💾 Event **#{evt.name}** saved as unpublished.", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def discard_draft(event, draft)
    EventDraft.delete(draft.id)
    event.update_message(content: '❌ Draft discarded.', embeds: [], components: [])
  end

  def persist_draft(draft, status:)
    if draft.persisted?
      evt = Event.find(draft.event_id)
      evt.update!(draft.to_event_attributes.merge(status: status, scheduled: (status == :scheduled)))
      evt.emojis = draft.emojis if draft.emojis.any?
      evt
    else
      attrs = draft.to_event_attributes.merge(status: status, scheduled: (status == :scheduled))
      evt = Event.create!(attrs)
      evt.emojis = draft.emojis if draft.emojis.any?
      evt
    end
  end

  # ---------------------------------------------------------------------------
  # Existing event management
  # ---------------------------------------------------------------------------

  def unpublish_event(event, evt)
    event.defer_update
    evt.update!(status: :unpublished)
    evt.unschedule
    event.edit_response content: "⏸️ Event **#{evt.name}** unpublished.", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def republish_event(event, evt)
    unless evt.schedulable?
      return event.respond(content: 'Cannot republish: the event is missing required information.', ephemeral: true)
    end

    event.defer_update
    evt.update!(status: :scheduled)
    bot_schedule(evt)
    event.edit_response content: "▶️ Event **#{evt.name}** republished and scheduled.", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def cancel_event(event, evt)
    event.defer_update
    evt.update!(status: :cancelled)
    evt.unschedule
    event.edit_response content: "🚫 Event **#{evt.name}** has been cancelled.", embeds: [event_dashboard_embed(evt)] do |_, view|
      render_event_management_components(view, evt)
    end
  end

  def delete_event(event, evt)
    unless evt.unpublished?
      return event.respond(content: 'Only unpublished events can be permanently deleted.', ephemeral: true)
    end

    event.defer_update
    name = evt.name || "Untitled_#{evt.id}"
    evt.destroy
    event.edit_response content: "🗑️ Event **#{name}** has been permanently deleted.", embeds: [], components: []
  end

  def duplicate_event(event, evt)
    user = User.find_by(discord_id: event.user.id)
    return event.respond(content: 'Could not identify your user record.', ephemeral: true) unless user

    draft = EventDraft.create(
      organizer_id: user.id,
      name: generate_duplicate_name(evt.name),
      location: evt.location,
      channel: evt.channel,
      message: evt.message,
      emojis: evt.emojis.to_a,
      start_time: nil,
      end_time: nil,
      message_rides_at: nil,
      collect_rides_at: nil,
      repeats_every: evt.repeats_every
    )

    event.respond content: "📄 Created a template from **#{evt.name}**. Set new times and publish when ready.", embeds: [event_dashboard_embed(draft)] do |_, view|
      render_builder_components(view, draft)
    end
  end
end
