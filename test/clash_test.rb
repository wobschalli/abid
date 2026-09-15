require_relative 'test_helper'

class ClashTest < AbidTest
  def test_stores_pairs_in_a_canonical_order
    a = make_user('a')
    b = make_user('b')
    low, high = [a.id, b.id].minmax

    clash = Clash.add(high, low)

    assert_equal low, clash.user_id
    assert_equal high, clash.other_user_id
  end

  def test_adding_the_same_pair_twice_is_idempotent
    a = make_user('a')
    b = make_user('b')

    Clash.add(a.id, b.id)
    Clash.add(b.id, a.id)

    assert_equal 1, Clash.count
  end

  def test_refuses_a_self_clash
    a = make_user('a')

    assert_nil Clash.add(a.id, a.id)
    assert_equal 0, Clash.count
  end

  def test_ids_for_looks_in_both_directions
    a = make_user('a')
    b = make_user('b')
    c = make_user('c')
    Clash.add(a.id, b.id)
    Clash.add(c.id, a.id)

    assert_equal [b.id, c.id].sort, Clash.ids_for(a.id).sort
    assert_equal [a.id], Clash.ids_for(b.id)
  end

  def test_remove_deletes_regardless_of_order
    a = make_user('a')
    b = make_user('b')
    Clash.add(a.id, b.id)

    Clash.remove(b.id, a.id)

    assert_equal 0, Clash.count
  end

  def test_map_for_returns_both_directions
    a = make_user('a')
    b = make_user('b')
    Clash.add(a.id, b.id)

    map = Clash.map_for([a.id, b.id])

    assert_equal [b.id], map[a.id]
    assert_equal [a.id], map[b.id]
  end

  # The board reads this map for every rider on screen; a default_proc would
  # silently grow the hash on each miss.
  def test_map_for_does_not_insert_on_missing_keys
    a = make_user('a')
    map = Clash.map_for([a.id])

    assert_equal [], map[-1]
    refute map.key?(-1)
  end
end
