# Materialises upcoming occurrences from recurring series.
#
# Called from two places that can fire at the same moment — the bot's tick and
# the coordinator's "Generate now" button — so the whole run takes a Postgres
# advisory lock. The unique index on [series_id, occurrence_date] is the real
# backstop; this just stops two processes doing the same work and logging
# confusing duplicate-key rescues.
class EventGenerator
  # Arbitrary but fixed: 'ABID' as bytes.
  LOCK_KEY = 0x4142_4944

  def self.call(...)
    new(...).call
  end

  # @param from [Date] first date to consider
  # @param only [EventSeries, nil] a single series, or nil for every active one
  def initialize(from: Time.zone.today, only: nil)
    @from = from
    @only = only
  end

  # @return [Array<Event>] occurrences created or already present
  def call
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
      series.flat_map { |s| s.generate_upcoming(from: @from) }
    end
  end

  private

  def series
    return [@only].compact if @only

    EventSeries.generatable.to_a
  end
end
