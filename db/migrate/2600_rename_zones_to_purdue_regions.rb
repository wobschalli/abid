class RenameZonesToPurdueRegions < ActiveRecord::Migration[8.0]
  # The old zones were placeholders lifted from a design mock and meant nothing
  # in West Lafayette. This maps them onto the real regions.
  #
  # Hard-coded rather than read from Location::ZONES on purpose: a migration
  # that reads a constant rewrites itself the next time that constant changes,
  # and then `rake db:migrate` on a fresh database produces different data than
  # it did last month.
  MAP = {
    'Campus' => 'On-campus',
    'Downtown' => 'Chauncey',
    'North' => 'Northwestern',
    'East' => 'Lafayette'
  }.freeze

  TABLES = %w[locations rides].freeze

  def up
    remap(MAP)
  end

  def down
    # 'Klondike' has no legacy pre-image, so rows holding it are left alone.
    remap(MAP.invert)
  end

  private

  # Both tables, because rides.zone is a denormalised copy that WINS over the
  # location's zone (see Ride#zone) — fixing locations alone would change
  # nothing on the board.
  def remap(mapping)
    TABLES.each do |table|
      report_unmapped(table, mapping.keys)

      mapping.each do |from, to|
        count = select_value(<<~SQL).to_i
          WITH updated AS (
            UPDATE #{table} SET zone = #{quote(to)}, updated_at = NOW()
             WHERE zone = #{quote(from)}
            RETURNING 1
          ) SELECT count(*) FROM updated
        SQL
        say "#{table}: #{count} rows #{from} -> #{to}", true if count.positive?
      end
    end
  end

  # Anything unrecognised is LEFT AS IS, not nulled. Nulling is irreversible,
  # and now that RideBoard#queue_groups gives unknown zones their own visible
  # bucket, the lossless option is also the safe one. This is the only place
  # these rows will ever be listed, so list them.
  def report_unmapped(table, expected)
    quoted = expected.map { |zone| quote(zone) }.join(', ')
    rows = select_rows(<<~SQL)
      SELECT zone, count(*) FROM #{table}
       WHERE zone IS NOT NULL AND zone <> ''
         AND zone NOT IN (#{quoted})
       GROUP BY zone ORDER BY 2 DESC
    SQL
    return if rows.empty?

    total = rows.sum { |(_, count)| count.to_i }
    say "#{table}: #{total} rows have an unmapped zone and were LEFT UNCHANGED:", true
    rows.each { |(zone, count)| say "  #{zone.inspect} x#{count}", true }
  end
end
