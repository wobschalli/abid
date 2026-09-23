require_relative 'test_helper'

# The rule of the snipes channel. The two promises that matter most: a
# snipe of someone who opted out is removed SILENTLY, and nobody is ever told
# their photo was removed when it was not.
class SnipesEnforcerTest < AbidTest
  class FakeAttachment
    def initialize(image) = @image = image
    def image? = @image
  end

  class FakeEmbed
    attr_reader :type, :image

    def initialize(type: 'rich', image: nil)
      @type = type
      @image = image
    end
  end

  class FakeUser
    attr_reader :id

    def initialize(id, bot: false)
      @id = id
      @bot = bot
    end

    def bot_account? = @bot
  end

  class FakeChannelRef
    attr_reader :id, :name

    def initialize(id, name = 'snipes')
      @id = id
      @name = name
    end
  end

  class FakeMessage
    attr_reader :id, :channel, :author, :attachments, :embeds, :mentions, :deleted_with

    def initialize(channel_id:, author:, attachments: [], embeds: [], mentions: [], delete_raises: nil)
      @id = 555
      @channel = FakeChannelRef.new(channel_id)
      @author = author
      @attachments = attachments
      @embeds = embeds
      @mentions = mentions
      @delete_raises = delete_raises
      @deleted_with = nil
    end

    def delete(reason = nil)
      raise @delete_raises if @delete_raises

      @deleted_with = reason
    end

    def deleted? = !@deleted_with.nil?
  end

  class FakeDiscordUser
    attr_reader :dms

    def initialize = @dms = []
    def dm(text) = @dms << text
  end

  class FakeBot
    attr_reader :users

    def initialize = @users = Hash.new { |h, k| h[k] = FakeDiscordUser.new }
    def user(id) = @users[id]
    def dms_to(id) = @users.key?(id) ? @users[id].dms : []
  end

  SNIPES_ID = 1_400_000_000_000_000_001
  OTHER_ID  = 1_400_000_000_000_000_002

  def setup
    super
    server = Server.create!(name: "S#{next_discord_id}", discord_id: next_discord_id)
    @channel = Channel.create!(name: 'snipes', discord_id: SNIPES_ID, server: server, purpose: 'snipes')
    @bot = FakeBot.new
    @poster = FakeUser.new(7001)
  end

  def enforce(message) = Snipes::Enforcer.new(@bot).call(message)

  def image = FakeAttachment.new(true)

  def opted_out_member(discord_id)
    User.create!(name: 'Shy', username: "shy#{discord_id}", discord_id: discord_id,
                 password: 'x' * 10, snipes_opt_out: true)
  end

  # --- scope ------------------------------------------------------------------

  def test_messages_elsewhere_are_ignored
    msg = FakeMessage.new(channel_id: OTHER_ID, author: @poster, attachments: [image])

    result = enforce(msg)

    assert_equal :not_snipes_channel, result.status
    refute msg.deleted?
  end

  def test_nothing_happens_when_no_snipes_channel_is_configured
    @channel.update!(purpose: nil)
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: @poster, attachments: [image])

    assert_equal :not_snipes_channel, enforce(msg).status
    refute msg.deleted?
  end

  def test_text_only_and_non_image_files_are_not_snipes
    text = FakeMessage.new(channel_id: SNIPES_ID, author: @poster)
    pdf = FakeMessage.new(channel_id: SNIPES_ID, author: @poster, attachments: [FakeAttachment.new(false)])

    assert_equal :not_a_snipe, enforce(text).status
    assert_equal :not_a_snipe, enforce(pdf).status
    refute text.deleted?
    refute pdf.deleted?
  end

  def test_a_bots_image_is_left_alone
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: FakeUser.new(1, bot: true), attachments: [image])

    assert_equal :not_a_snipe, enforce(msg).status
    refute msg.deleted?
  end

  # --- the rule ---------------------------------------------------------------

  def test_a_tagged_snipe_of_someone_who_is_fine_with_it_stays
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: @poster, attachments: [image],
                          mentions: [FakeUser.new(8001)])

    result = enforce(msg)

    assert_equal :ok, result.status
    assert_equal [8001], result.mentioned
    refute msg.deleted?
    assert_empty @bot.dms_to(7001)
  end

  def test_an_untagged_image_is_removed_and_the_poster_is_told_why
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: @poster, attachments: [image])

    result = capture_io { @r = enforce(msg) }.then { @r }

    assert_equal :untagged, result.status
    assert msg.deleted?, 'untagged snipe survived'
    assert_equal 1, @bot.dms_to(7001).size, 'poster was not told'
    assert_includes @bot.dms_to(7001).first, '@mention'
    assert_includes @bot.dms_to(7001).first, '#snipes'
  end

  def test_a_snipe_of_someone_who_opted_out_is_removed_silently
    opted_out_member(8002)
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: @poster, attachments: [image],
                          mentions: [FakeUser.new(8002)])

    result = enforce(msg)

    assert_equal :opted_out, result.status
    assert msg.deleted?
    assert_empty @bot.dms_to(7001), 'announced an opt-out to the poster'
  end

  # A group photo needs everyone in it to be okay with it.
  def test_one_opted_out_person_among_several_tags_is_enough
    opted_out_member(8003)
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: @poster, attachments: [image],
                          mentions: [FakeUser.new(8001), FakeUser.new(8003), FakeUser.new(8004)])

    assert_equal :opted_out, enforce(msg).status
    assert msg.deleted?
  end

  def test_a_pasted_image_url_counts_as_an_image
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: @poster,
                          embeds: [FakeEmbed.new(type: 'image', image: 'https://x/y.png')])

    result = capture_io { @r = enforce(msg) }.then { @r }

    assert_equal :untagged, result.status
    assert msg.deleted?
  end

  def test_a_link_preview_is_not_an_image
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: @poster, embeds: [FakeEmbed.new(type: 'rich')])

    assert_equal :not_a_snipe, enforce(msg).status
  end

  # --- when the delete itself fails ------------------------------------------

  def test_a_failed_delete_never_tells_the_poster_their_photo_was_removed
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: @poster, attachments: [image],
                          delete_raises: RuntimeError.new('403 Missing Permissions'))

    result = capture_io { @r = enforce(msg) }.then { @r }

    assert_equal :delete_failed, result.status
    refute result.deleted
    assert_empty @bot.dms_to(7001), 'DMed "removed" about a photo that is still up'
  end

  # Shaped like Discordrb::Errors::NoPermission without loading discordrb: the
  # enforcer keys the hint on the class name.
  class NoPermission < RuntimeError; end

  def test_a_permission_failure_names_the_missing_permission_in_the_log
    msg = FakeMessage.new(channel_id: SNIPES_ID, author: @poster, attachments: [image],
                          delete_raises: NoPermission.new('403'))

    _out, err_text = capture_io { enforce(msg) }

    assert_includes err_text, 'Manage Messages'
  end
end
