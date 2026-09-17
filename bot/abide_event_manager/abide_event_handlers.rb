module AbideEventHandlers

  private

  def set_button_handlers
    client.button custom_id: /event_edit_basics_(.+)/ do |event|
      with_draft_or_event(event) { |draft| show_edit_basics_modal(event, draft) }
    end

    client.button custom_id: /event_edit_timing_(.+)/ do |event|
      with_draft_or_event(event) { |draft| show_edit_timing_modal(event, draft) }
    end

    client.button custom_id: /event_edit_reactions_(.+)/ do |event|
      with_draft_or_event(event) { |draft| show_edit_reactions_modal(event, draft) }
    end

    client.button custom_id: /event_publish_(.+)/ do |event|
      with_draft(event) { |draft| publish_draft(event, draft) }
    end

    client.button custom_id: /event_save_unpublished_(.+)/ do |event|
      with_draft(event) { |draft| save_draft_as_unpublished(event, draft) }
    end

    client.button custom_id: /event_discard_(.+)/ do |event|
      with_draft(event) { |draft| discard_draft(event, draft) }
    end

    client.button custom_id: /event_unpublish_(\d+)/ do |event|
      with_event(event) { |evt| unpublish_event(event, evt) }
    end

    client.button custom_id: /event_republish_(\d+)/ do |event|
      with_event(event) { |evt| republish_event(event, evt) }
    end

    client.button custom_id: /event_cancel_(\d+)/ do |event|
      with_event(event) { |evt| cancel_event(event, evt) }
    end

    client.button custom_id: /event_delete_(\d+)/ do |event|
      with_event(event) { |evt| delete_event(event, evt) }
    end

    client.button custom_id: /event_duplicate_(\d+)/ do |event|
      with_event(event) { |evt| duplicate_event(event, evt) }
    end
  end

  def set_select_handlers
    client.select_menu custom_id: /event_set_channel_(.+)/ do |event|
      with_draft_or_event(event) do |draft|
        channel_id = event.values.first.to_i
        channel = Channel.find_by(discord_id: channel_id)
        draft.channel = channel if channel
        refresh_dashboard(event, draft)
      end
    end
  end

  def set_modal_handlers
    client.modal_submit custom_id: /event_modal_basics_(.+)/ do |event|
      with_draft_or_event(event) { |draft| handle_edit_basics(event, draft) }
    end

    client.modal_submit custom_id: /event_modal_timing_(.+)/ do |event|
      with_draft_or_event(event) { |draft| handle_edit_timing(event, draft) }
    end

    client.modal_submit custom_id: /event_modal_reactions_(.+)/ do |event|
      with_draft_or_event(event) { |draft| handle_edit_reactions(event, draft) }
    end
  end
end
