class Discordrb::Bot
  # @param channel id [Discordrb::Channel, String, Integer]
  # @param message [String]
  # @param tts [true, false]
  # @param embeds [Hash, Discordrb::Webhooks::Embed, Array<Hash>, Array<Discordrb::Webhooks::Embed> nil]
  # @param attachments [Array<File>]
  # @param allowed_mentions [Hash, Discordrb::AllowedMentions, false, nil]
  # @param message_reference [Hash, Discordrb::AllowedMentions, false, nil]
  # @param components [View, Array<Hash>]
  # @param timeout [Float, nil]
  # @returns [Discordrb::Message]
  def send(channel, message, tts:false, embeds:nil, attachments:nil, allowed_mentions:false, message_reference:nil, components:nil, timeout:nil)
    if timeout
      send_temporary_message channel, message, timeout, tts, embeds, attachments, allowed_mentions, message_reference, components
    else
      send_message channel, message, tts, embeds, attachments, allowed_mentions, message_reference, components
    end
  end
end
