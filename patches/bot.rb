module Discordrb::Events
  class ReactionEvent
    # discordrb stores @user_id but exposes only #user, which resolves through
    # `server.member(id)`. On a reaction *remove* the gateway sends no member
    # payload, so #user can cost an HTTP round trip — for an id we already have
    # and only need to look up in our own database.
    attr_reader :user_id
  end
end

class Discordrb::Bot
  # NOTE: this overrides Object#send on every bot instance. Any metaprogramming
  # that reaches for `bot.send(:some_method)` will try to post a Discord message
  # instead.
  #
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
