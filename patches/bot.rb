# Hybrid command support remains unfinished
class HybridContext
  attr_reader :event, :args, :user, :server, :channel

  def initialize(event, args, is_slash)
    @event, @args, @is_slash = event, args, is_slash
    @user, @server, @channel = event.user, event.server, event.channel
  end

  def slash?
    @is_slash
  end

  def defer(ephemeral: false)
    slash? ? @event.defer(ephemeral: ephemeral) : @event.typing
  end

  def respond(content, ephemeral: false)
    if slash?
      @event.respond(content: content, ephemeral: ephemeral)
    else
      @prefix_message = ephemeral ? @user.pm(content) : @event.respond(content)
    end
  end

  def edit(content)
    if slash?
      @event.edit_response(content: content)
    else
      @prefix_message ? @prefix_message.edit(content) : @event.respond(content)
    end
  end
end

class HybridCommand
  attr_reader :name, :description, :options, :subcommands, :block

  def initialize(bot, name, description)
    @bot, @name, @description = bot, name, description
    @options = []
    @subcommands = {}
    @block = nil
  end

  def string(name, desc, **kwargs); add_option(:string, name, desc, **kwargs); end
  def integer(name, desc, **kwargs); add_option(:integer, name, desc, **kwargs); end
  def number(name, desc, **kwargs); add_option(:number, name, desc, **kwargs); end # Floating-point
  def boolean(name, desc, **kwargs); add_option(:boolean, name, desc, **kwargs); end
  def user(name, desc, **kwargs); add_option(:user, name, desc, **kwargs); end
  def channel(name, desc, **kwargs); add_option(:channel, name, desc, **kwargs); end
  def role(name, desc, **kwargs); add_option(:role, name, desc, **kwargs); end

  def add_option(type, name, desc, required: false, choices: nil, autocomplete: nil)
    @options << {
      type: type, name: name, desc: desc, required: required,
      choices: choices, autocomplete: autocomplete
    }
  end

  def action(&block)
    @block = block
  end

  def subcommand(sub_name, desc: nil, &block)
    sub_name = sub_name.to_sym
    sub = @subcommands[sub_name]

    if sub.nil?
      raise ArgumentError, "Description required for new subcommand" if desc.nil?
      sub = HybridCommand.new(@bot, sub_name, desc)
      @subcommands[sub_name] = sub
    end

    yield(sub) if block_given?
    sub
  end

  def register!(server_id: nil)
    if server_id
      @bot.register_application_command(@name, @description, server_id) do |builder|
        if @subcommands.any?
          @subcommands.values.each do |sub|
            builder.subcommand(sub.name, sub.description) do |sub_builder|
              sub.options.each do |opt|
                sub_builder.send(opt[:type], opt[:name], opt[:desc], required: opt[:required])
              end
            end
          end
        else
          @options.each do |opt|
            builder.send(opt[:type], opt[:name], opt[:desc], required: opt[:required])
          end
        end
        puts "Synced Command #{@name} to server #{server_id}"
      end
    else
      return unless ENV['SYNC_COMMANDS'] == 'true'
      @bot.register_application_command(@name, @description) do |builder|
        if @subcommands.any?
          @subcommands.values.each do |sub|
            builder.subcommand(sub.name, sub.description) do |sub_builder|
              sub.options.each do |opt|
                sub_builder.send(opt[:type], opt[:name], opt[:desc], required: opt[:required])
              end
            end
          end
        else
          @options.each do |opt|
            builder.send(opt[:type], opt[:name], opt[:desc], required: opt[:required])
          end
        end
        puts "Synced Command #{@name} globally"
      end
    end
  end

  def set!
    if @subcommands.empty?
      @bot.application_command(@name) do |event|
        execute_slash(event, self)
      end
    else
      @subcommands.values.each do |sub|
        @bot.application_command(@name).subcommand(sub.name) do |event|
          execute_slash(event, sub)
        end
      end
    end

    @bot.command(@name, description: @description) do |event, *raw_args|
      execute_prefix(event, raw_args)
    end
  end

  private

  def execute_slash(event, target_cmd)
    args = {}
    target_cmd.options.each do |opt|
      args[opt[:name]] = event.options[opt[:name].to_s]
    end
    ctx = HybridContext.new(event, args, true)
    target_cmd.block.call(ctx) if target_cmd.block
  end
end

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

  def hybrid_commands
    @hybrid_commands ||= {}
  end

  def hybrid_command(name, description: nil, &block)
    name = name.to_sym
    cmd = hybrid_commands[name]

    if cmd.nil?
      raise ArgumentError, "Description required for new hybrid command" if description.nil?
      cmd = HybridCommand.new(self, name, description)
      hybrid_commands[name] = cmd
    end

    yield(cmd) if block_given?

    cmd
  end

  def set_hybrid_commands!
    hybrid_commands.values.each(&:set!)
  end

  def register_hybrid_commands!(server_id: nil)
    hybrid_commands.values.each do |cmd|
      cmd.register!(server_id: server_id)
    end
  end
end
