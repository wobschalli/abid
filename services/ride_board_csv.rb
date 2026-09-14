require 'csv'

# One column per car, riders down the rows, capacity on the last line — the same
# shape the design's exportCsv produces, plus a trailing block for anyone still
# unseated so the sheet is safe to print and hand out.
class RideBoardCsv
  def initialize(board)
    @board = board
  end

  def to_csv
    cars = @board.cars
    return no_drivers_csv if cars.empty?

    depth = [cars.map { |c| c.passengers.size }.max, 1].max

    CSV.generate do |csv|
      csv << cars.map(&:name)
      csv << cars.map { |c| c.zone.to_s }

      depth.times do |i|
        csv << cars.map { |c| c.passengers[i]&.display_name.to_s }
      end

      csv << cars.map { |c| "#{c.used}/#{c.seats}" }

      unless @board.pool.empty?
        csv << []
        csv << ['Still waiting']
        @board.pool.each { |r| csv << [r.display_name, r.zone.to_s, r.address.to_s] }
      end
    end
  end

  private

  def no_drivers_csv
    CSV.generate do |csv|
      csv << ['No drivers assigned for this event']
      csv << ['Still waiting'] unless @board.pool.empty?
      @board.pool.each { |r| csv << [r.display_name, r.zone.to_s, r.address.to_s] }
    end
  end
end
