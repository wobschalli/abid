class Discordrb::Webhooks::View::RowBuilder
  BUTTON_STYLES = {
    primary: 1,
    secondary: 2,
    success: 3,
    danger: 4,
    link: 5
  }.freeze

  COMPONENT_TYPES = {
    action_row: 1,
    button: 2,
    string_select: 3,
    user_select: 5,
    role_select: 6,
    mentionable_select: 7,
    channel_select: 8
  }.freeze

  def button(style:, label: nil, emoji: nil, custom_id: nil, disabled: nil, url: nil)
    style = BUTTON_STYLES[style] || style

    emoji = case emoji
            when Integer, String
              emoji.is_a?(Integer) ? { id: emoji } : { name: emoji } #emoji codepoints return positive integers
            when nil #allow no emoji to be sent
              nil
            else
              emoji&.to_h
            end

    @components << { type: COMPONENT_TYPES[:button], label: label, emoji: emoji, style: style, custom_id: custom_id, disabled: disabled, url: url }
  end

  def option(label:, value:, description: nil, emoji: nil, default: nil)
    emoji = case emoji
            when Integer, String
              emoji.is_a?(Integer) ? { id: emoji } : { name: emoji }
            when nil
              nil
            else
              emoji&.to_h
            end

    @options << { label: label, value: value, description: description, emoji: emoji, default: default }
  end
end
