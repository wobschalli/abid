class Discordrb::Bot
  def send(channel, message, tts:false, embeds:nil, attachments:nil, allowed_mentions:false, message_reference:nil, components:nil, timeout:nil)
    if timeout
      send_temporary_message channel, message, timeout, tts, embeds, attachments, allowed_mentions, message_reference, components
    else
      send_message channel, message, tts, embeds, attachments, allowed_mentions, message_reference, components
    end
  end
end
