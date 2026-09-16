require_relative 'test_helper'
require 'tempfile'
require_relative '../db/import_riders'

# The census export is read as-is, straight from Google Forms, so the parsing
# has to cope with the real question wording rather than a cleaned-up file.
class ImportCensusTest < AbidTest
  HEADERS = [
    'Timestamp',
    'Preferred First Name',
    'Last Name',
    'Year',
    'Phone Number',
    'Discord handle (we use discord for all our official communication). ' \
      'This helps us identify you but also prevents us from accidentally deleting you.',
    'Where do you live while at Purdue?',
    'How many seats do you have available for riders?'
  ].freeze

  def csv_with(*rows)
    file = Tempfile.new(['census', '.csv'])
    file.puts HEADERS.map { |h| %("#{h}") }.join(',')
    rows.each { |r| file.puts r.map { |v| %("#{v}") }.join(',') }
    file.flush
    file
  end

  def parse(*rows) = Abid::ImportRiders.parse(csv_with(*rows).path)

  def test_joins_the_two_name_columns
    # Both headers match /name/i. Read naively, "Last Name" wins the mapping and
    # the first-name answer is discarded.
    row = parse(['2026-08-01', 'Laura', 'Sun', 'Sophomore', '765-123-4567',
                 'Laurasun0', 'Windsor', '']).first

    assert_equal 'Laura Sun', row.name
    assert_equal 'Laurasun0', row.handle
    assert_equal '7651234567', row.phone
    assert_equal 'Windsor', row.residence
  end

  def test_reads_the_seats_column_as_capacity
    row = parse(['2026-08-01', 'Joseph', 'Huang', 'Grad Student', '765-123-4567',
                 'josephjhuang', 'Lark', '3']).first

    assert_equal 3, row.capacity
  end

  def test_turns_the_academic_year_into_a_graduation_year
    rows = parse(
      ['2026-08-01', 'A', 'One', 'Freshman',  '765-123-4567', 'a1', 'Cary', ''],
      ['2026-08-01', 'B', 'Two', 'Senior',    '765-123-4568', 'b2', 'Cary', ''],
      ['2026-08-01', 'C', 'Три', 'Grad Student', '765-123-4569', 'c3', 'Cary', '']
    )

    # Anchored on the current academic year, which starts in August.
    today = Time.zone.today
    start = today.month >= 8 ? today.year : today.year - 1

    assert_equal start + 4, rows[0].grad_year, 'a freshman graduates in four years'
    assert_equal start + 1, rows[1].grad_year
    assert_nil rows[2].grad_year, 'a grad student has no undergraduate year to infer'
  end

  def test_a_name_typed_into_the_handle_box_still_resolves
    # "David cochern" is not literally a handle — Discord usernames have no
    # spaces — but it is @davidcochern with a space in it, and the relaxed tier
    # is guarded by uniqueness in both directions.
    user = User.create!(name: 'David', username: 'davidcochern',
                        discord_id: next_discord_id, password: 'x' * 10)
    rows = parse(['2026-08-01', 'David', 'Cochern', 'Junior', '765-123-4567',
                  'David cochern', 'Wiley', ''])

    result = RiderImport.new(rows, mark_active: true).call.first

    assert_equal user, result.user
    assert_equal :relaxed, result.how
    assert user.reload.active?
  end

  def test_gibberish_in_the_handle_box_matches_nobody
    User.create!(name: 'Sonny Ruan', username: 'sunnyo.0',
                 discord_id: next_discord_id, password: 'x' * 10)
    rows = parse(['2026-08-01', 'Sunny', 'Ruan', 'Senior', '765-123-4567',
                  'Yea that', 'Lark', '4'])

    result = RiderImport.new(rows, mark_active: true).call.first

    # Sonny and Sunny are probably the same person, but "probably" is exactly
    # what must not attach one student's phone number to another's account.
    assert_nil result.user
    assert_equal :unmatched, result.how
  end
end
