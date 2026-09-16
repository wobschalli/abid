# Fills in home location, phone and car capacity for people who already exist,
# from the roster the coordinator keeps outside this app (the Google Form
# export, or the sheet it feeds).
#
# It never creates a User. Everyone comes from the Discord member sync, so a row
# that matches nobody means the handle is stale or that person is not in the
# server — both of which a human needs to look at, and neither of which is fixed
# by inventing an account.
#
# The whole design point is that a WRONG match is much worse than no match. A
# mismatch attaches one student's phone number and home address to another
# student's account, and nothing downstream would ever flag it — the board would
# just start sending a driver to the wrong building. So matching is tiered by
# confidence, anything ambiguous is refused rather than guessed, and every
# refusal is reported for a human to resolve.
class RiderImport
  Row = Struct.new(:name, :handle, :phone, :residence, :capacity, :grad_year, keyword_init: true)

  Result = Struct.new(:row, :user, :how, :changes, :residence_match, :problem,
                      keyword_init: true) do
    def matched? = user.present?
  end

  # Ordered by confidence. `:username` and `:display_name` are exact; `:relaxed`
  # only strips the punctuation Discord allows in handles, which is what makes
  # 'TheOscar' find '_theoscar' and 'amiable' find 'amiable_'.
  #
  # The last two exist because people set their Discord display name to their
  # first name, or first name plus an initial: 'Casey Flynn' shows up as
  # 'Casey F.' and 'Ranbir Atwal' as plain 'Ranbir'. Both are only ever used
  # when exactly one account answers to the key AND exactly one spreadsheet row
  # claims that account — 'Casey' alone matches three people and must match
  # none of them.
  HOW = %i[username display_name relaxed name_initial first_name].freeze

  # Tiers where the key is a person's name rather than something they chose as
  # an identifier. Two different rows landing on one account here means the name
  # was not specific enough, so both are refused.
  WEAK = %i[name_initial first_name].freeze

  # mark_active: the census is a statement of "I am part of this fellowship this
  # year", which is exactly what the Active roster means. The rides sheet is
  # not — someone can appear on it as a one-off passenger — so this is opt-in
  # per import rather than something every import does.
  def initialize(rows, scope: User.all, dry_run: false, mark_active: false)
    @rows = rows
    @scope = scope
    @dry_run = dry_run
    @mark_active = mark_active
    index!
  end

  def call
    resolved = @rows.map { |row| [row, *find_user(row)] }

    # The index guarantees one account per key. It cannot see the other
    # direction: two different rows — Bella Cho and Bella Liu — both landing on
    # the single Discord 'Bella'. One of them is wrong and nothing here can say
    # which, so both are refused.
    contested = resolved
                .select { |_, user, how| user && WEAK.include?(how) }
                .group_by { |_, user, _| user.id }
                .select { |_, group| group.map(&:first).uniq.size > 1 }
                .keys

    resolved.map do |row, user, how|
      if user.nil?
        Result.new(row: row, how: :unmatched)
      elsif contested.include?(user.id)
        Result.new(row: row, how: :unmatched, problem: :ambiguous_name)
      else
        location, residence_match = find_location(row)
        Result.new(row: row, user: user, how: how, residence_match: residence_match,
                   changes: apply(user, row, location))
      end
    end
  end

  private

  # Built once. Any tier that turns out to be ambiguous — the same key claimed
  # by two different people — is dropped from the index entirely rather than
  # resolved arbitrarily. 'nate' matching three accounts must match none.
  def index!
    users = @scope.to_a
    @by_username = unique_index(users) { |u| normal(u.username) }
    @by_display  = unique_index(users) { |u| normal(u.name) }
    @by_relaxed  = unique_index(users) { |u| relax(u.username) }
    @relaxed_display = unique_index(users) { |u| relax(u.name) }
    @by_initial  = unique_index(users) { |u| name_initial(u.name) }
    @by_first    = unique_index(users) { |u| first_name(u.name) }
  end

  # 'Casey F.' and 'Casey Flynn' both reduce to 'casey f'.
  def name_initial(value)
    first, last = normal(value).to_s.split(/\s+/, 2)
    return if first.blank? || last.blank?

    "#{first} #{last[0]}"
  end

  def first_name(value) = normal(value).to_s.split(/\s+/).first.presence

  def unique_index(users)
    counts = Hash.new(0)
    index = {}
    users.each do |user|
      key = yield(user)
      next if key.blank?

      counts[key] += 1
      index[key] = user
    end
    index.reject { |key, _| counts[key] > 1 }
  end

  def normal(value) = value.to_s.strip.downcase.presence

  # Discord usernames allow . and _ and are case-insensitive; people write them
  # down without either. Stripping both is a real normalisation, not a fuzzy
  # guess — unlike substring matching, which is how 'wob' would wrongly claim
  # 'wibblewobblebobble'.
  def relax(value) = normal(value)&.gsub(/[^a-z0-9]/, '').presence

  def find_user(row)
    handle = row.handle
    if handle.present?
      found = @by_username[normal(handle)]
      return [found, :username] if found
    end

    found = @by_display[normal(row.name)]
    return [found, :display_name] if found

    # The handle people wrote down is often their display name instead.
    found = @by_display[normal(handle)] if handle.present?
    return [found, :display_name] if found

    if handle.present?
      found = @by_relaxed[relax(handle)] || @relaxed_display[relax(handle)]
      return [found, :relaxed] if found
    end

    found = @relaxed_display[relax(row.name)]
    return [found, :relaxed] if found

    found = @by_initial[name_initial(row.name)]
    return [found, :name_initial] if found

    found = @by_first[first_name(row.name)]
    return [found, :first_name] if found

    [nil, :unmatched]
  end

  # Returns [location, how]. `:none` means the text named nowhere we know, which
  # is reported rather than papered over — a location invented from a free-text
  # answer would land with no zone and quietly break the queue grouping.
  def find_location(row)
    text = row.residence.to_s.strip
    return [nil, :blank] if text.empty?

    exact = Location.search_by_name(text).first
    return [exact, :exact] if exact

    # 'Earhart 267', 'Apt lark', 'Dorm - Meredith South', 'Riverbend apts 202 S
    # River Rd ...' — the building name is in there with noise around it. Try
    # the longest alias that appears as a whole word.
    found = longest_alias_match(text)
    found ? [found, :partial] : [nil, nil]
  end

  def longest_alias_match(text)
    key = text.downcase
    candidates = Location.all.select do |location|
      ([location.name] + location.aliases.to_a).any? do |term|
        term = term.to_s.downcase
        term.present? && key.match?(/(?<![a-z0-9])#{Regexp.escape(term)}(?![a-z0-9])/)
      end
    end
    candidates.max_by { |location| ([location.name] + location.aliases.to_a).map { |t| t.to_s.length }.max }
  end

  # Only ever fills a blank. Someone who has set their own home location in the
  # dashboard has said something more current than a spreadsheet row, and an
  # import must not overwrite it.
  def apply(user, row, location)
    changes = {}
    # Not a blank-fill like the rest: filling out the census IS the statement,
    # so it sets the flag even on someone previously marked inactive. It never
    # un-marks anyone — not answering a form is not a resignation.
    changes[:active] = true if @mark_active && !user.active?
    changes[:phone] = row.phone if row.phone.present? && user.phone.blank?
    changes[:location_id] = location.id if location && user.location_id.blank?
    changes[:capacity] = row.capacity if row.capacity.present? && user.capacity.blank?
    changes[:grad_year] = row.grad_year if row.grad_year.present? && user.grad_year.blank?
    return changes if changes.empty? || @dry_run

    user.update!(changes)
    changes
  end
end
