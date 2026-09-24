require_relative 'test_helper'

class SnipesPreferenceTest < AbidTest
  def test_default_is_fine_with_snipes
    user = User.create!(name: 'New', username: "new#{next_discord_id}", discord_id: next_discord_id, password: 'x' * 10)

    refute user.snipes_opt_out
    assert_nil user.snipes_preference_at
  end

  def test_a_stranger_pressing_the_button_gets_a_row_and_the_flag
    discord_id = next_discord_id
    refute User.exists?(discord_id: discord_id)

    result = Snipes::Preference.set(discord_id: discord_id, opt_out: true,
                                    username: 'shy_person', display_name: 'Shy')

    assert result.changed
    user = User.find_by!(discord_id: discord_id)
    assert user.snipes_opt_out
    refute_nil user.snipes_preference_at
    assert_equal 'shy_person', user.username
  end

  def test_opting_back_in_clears_the_flag
    discord_id = next_discord_id
    Snipes::Preference.set(discord_id: discord_id, opt_out: true)

    result = Snipes::Preference.set(discord_id: discord_id, opt_out: false)

    assert result.changed
    refute User.find_by!(discord_id: discord_id).snipes_opt_out
  end

  def test_pressing_the_same_button_twice_is_a_noop
    discord_id = next_discord_id
    first = Snipes::Preference.set(discord_id: discord_id, opt_out: true)
    stamp = first.user.reload.snipes_preference_at

    second = Snipes::Preference.set(discord_id: discord_id, opt_out: true)

    refute second.changed
    assert_equal stamp, second.user.reload.snipes_preference_at, 'a no-op press moved the timestamp'
  end

  # A curated dashboard name must not be overwritten by whatever Discord sends
  # with the click — same rule as DiscordUserSync everywhere else.
  def test_an_existing_members_name_is_not_overwritten
    user = User.create!(name: 'Curated Name', username: 'curated', discord_id: next_discord_id, password: 'x' * 10)

    Snipes::Preference.set(discord_id: user.discord_id, opt_out: true, display_name: 'discord nick')

    assert_equal 'Curated Name', user.reload.name
    assert user.snipes_opt_out
  end

  def test_the_replies_say_what_state_you_are_in
    assert_includes Snipes::Preference.reply_for(true), "you're out"
    assert_includes Snipes::Preference.reply_for(false), 'back in'
  end

  # --- /toggle-sniping ----------------------------------------------------------

  def test_toggle_opts_a_snipable_person_out_then_back_in
    discord_id = next_discord_id

    first = Snipes::Preference.toggle(discord_id: discord_id, username: 'flip')
    assert first.opt_out, 'default is snipable, so the first toggle must opt out'
    assert User.find_by!(discord_id: discord_id).snipes_opt_out

    second = Snipes::Preference.toggle(discord_id: discord_id)
    refute second.opt_out
    refute User.find_by!(discord_id: discord_id).snipes_opt_out
  end

  def test_toggle_and_buttons_share_one_flag
    discord_id = next_discord_id
    Snipes::Preference.set(discord_id: discord_id, opt_out: true)

    result = Snipes::Preference.toggle(discord_id: discord_id)

    refute result.opt_out, 'a toggle after the opt-out button should opt back in'
  end

end
