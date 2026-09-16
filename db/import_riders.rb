# Imports rider details from a CSV export of the rides sign-up form.
#
#   rake import:riders[path/to/export.csv]          # dry run, writes nothing
#   rake import:riders[path/to/export.csv,apply]    # actually writes
#
# CSV rather than .xlsx on purpose: Google Forms exports it natively, it needs
# no gem, and — most importantly — it keeps the roster OUT of this repo. The
# file is 100-odd real students' phone numbers and home addresses; it must live
# wherever the coordinator keeps it, never in version control.
#
# Column headers are matched loosely, so the form's real questions work as-is
# ("Name (First, Last)", "Contact info (discord)", "Where do you live? (Dorm or
# Apartment name)") without anyone having to rename anything first.
require 'csv'

module Abid
  module ImportRiders
    # header fragment => Row field. First match wins, so put the specific ones
    # first: 'phone' has to be tested before 'contact', or a "Contact info
    # (discord)" column is read as a phone number.
    COLUMNS = [
      [/phone/i,               :phone],
      [/discord|contact/i,     :handle],
      [/where do you live|residence|dorm|apartment/i, :residence],
      [/capacity|seats/i,      :capacity],
      [/name/i,                :name]
    ].freeze

    module_function

    def call(path, apply: false)
      rows = parse(path)
      abort "no usable rows in #{path}" if rows.empty?

      results = RiderImport.new(rows, scope: User.all, dry_run: !apply).call
      report(results, apply: apply)
      results
    end

    def parse(path)
      table = CSV.read(path, headers: true)
      mapping = map_headers(table.headers)
      abort "could not find a name column in #{path}" unless mapping.value?(:name)

      merge(table.filter_map { |csv_row| build_row(csv_row, mapping) })
    end

    # The same person appears on more than one sheet, and the sheets know
    # different things: the form has their Discord handle, the database sheet
    # has their phone. Merging before matching is not tidying — it is what lets
    # a row that only had a phone number be matched at all, via the handle its
    # twin carried.
    #
    # Later rows win per field because the form is append-only, so the newest
    # answer is the most current one.
    def merge(rows)
      rows.each_with_object({}) do |row, merged|
        key = row.name.downcase
        existing = merged[key]
        if existing.nil?
          merged[key] = row
          next
        end

        RiderImport::Row.members.each do |field|
          value = row[field]
          existing[field] = value if value.present?
        end
      end.values
    end

    def map_headers(headers)
      headers.compact.to_h do |header|
        match = COLUMNS.find { |pattern, _| header.match?(pattern) }
        [header, match&.last]
      end.compact
    end

    def build_row(csv_row, mapping)
      values = Hash.new { |h, k| h[k] = nil }
      mapping.each do |header, field|
        value = csv_row[header].to_s.strip
        values[field] = value if value.present? && values[field].blank?
      end
      return if values[:name].blank?

      RiderImport::Row.new(
        name: clean_name(values[:name]),
        handle: clean_handle(values[:handle]),
        phone: clean_phone(values[:phone]),
        residence: values[:residence],
        capacity: values[:capacity].to_s[/\d+/]&.to_i
      )
    end

    # "Tim, Lee" and "Shujie, Luo" — the form asked for "First, Last" and people
    # obliged. The comma carries no information we can trust (a few answered
    # "Last,First"), so it is just removed rather than used to reorder.
    def clean_name(value) = value.to_s.gsub(/\s*,\s*/, ' ').squeeze(' ').strip

    def clean_handle(value)
      handle = value.to_s.strip.sub(/\Adiscord\s*:\s*/i, '').delete_prefix('@').strip
      # "Etasman (Elsa)", "bloonsaddict (dino)" — the handle, then who it is.
      handle = Regexp.last_match(1) if handle.match(/\A([A-Za-z0-9._]+)\s*\(/)
      # A phone number in the contact column is a phone number, not a handle.
      return '' if handle.delete('^0-9').length >= 7
      # "Laura Yue", "Christy Liu" — a name typed into the handle box. Discord
      # usernames cannot contain spaces, so this is never a handle.
      return '' if handle.include?(' ') || handle.length < 2

      handle
    end

    # Spreadsheets turn a phone column into floats: 7651234567.0.
    def clean_phone(value)
      digits = value.to_s.delete('^0-9')
      digits = digits[1..] if digits.length == 11 && digits.start_with?('1')
      digits.length == 10 ? digits : ''
    end

    def report(results, apply:)
      matched, unmatched = results.partition(&:matched?)
      changed = matched.select { |r| r.changes.present? }

      puts
      puts(apply ? '== applied ==' : '== DRY RUN — nothing written ==')
      puts "rows read:        #{results.size}"
      puts "matched a member: #{matched.size}"
      RiderImport::HOW.each do |how|
        count = matched.count { |r| r.how == how }
        puts "    by #{how}:".ljust(22) + count.to_s if count.positive?
      end
      puts "would update:     #{changed.size}" unless apply
      puts "updated:          #{changed.size}" if apply
      %i[phone location_id capacity].each do |field|
        count = changed.count { |r| r.changes.key?(field) }
        puts "    #{field}:".ljust(22) + count.to_s if count.positive?
      end

      # Matches made on a person's name rather than an identifier they chose.
      # Each is individually plausible and collectively they are most of the
      # value here, but 'Eileen Kuo' meeting a Discord 'Eileen Koh' is the exact
      # shape of a wrong one — so they are printed for a human to skim rather
      # than buried in a count.
      by_name = matched.select { |r| RiderImport::WEAK.include?(r.how) }
      if by_name.any?
        puts
        puts "matched on name (#{by_name.size}) — worth a glance, surnames are not checked:"
        by_name.each do |r|
          puts "    #{r.row.name.to_s.ljust(22)} -> #{r.user.name.to_s.ljust(18)} @#{r.user.username}"
        end
      end

      no_home = matched.select { |r| r.row.residence.present? && r.residence_match.nil? }
      if no_home.any?
        puts
        puts "residence not recognised (#{no_home.size}) — add to db/locations.rb if it is a real place:"
        no_home.map { |r| r.row.residence }.tally.sort_by { |_, n| -n }
               .each { |text, n| puts "    #{text.to_s.ljust(46)} x#{n}" }
      end

      return if unmatched.empty?

      puts
      puts "no matching Discord member (#{unmatched.size}) — stale handle, or not in the server."
      puts 'Left untouched on purpose: guessing here attaches one person\'s details to another.'
      unmatched.each { |r| puts "    #{r.row.name.to_s.ljust(26)} @#{r.row.handle}" }
    end
  end
end
