require 'csv'

# The rides sheet, in the shape the coordinator has always kept it by hand:
# one column per driver, riders stacked underneath, and a header spanning each
# service's group of drivers.
#
#            | Sunday School 9:30 AM        | Sunday Service 10:30 AM
#   Driver   | ian     caleb   tobin        | eugene   ranbir
#   Riders   | caitlin kylan r Renata       | ...      Andrew
#            | jalen  juno wa kylan m      |          senna tso
#   Van Total| 13                           | 48
#
# A whole DATE, not one occurrence: a Sunday has two services and the sheet
# that gets printed and handed round covers both. Exporting from either board
# gives you the same sheet.
#
# CSV rather than a real .xlsx because it opens in Excel and Sheets either way
# and needs no gem. The one thing it cannot carry is the cell shading on the
# driver row, which is decoration rather than information.
class RideBoardCsv
  LABEL_COLUMN = 1

  def initialize(board)
    @board = board
  end

  def to_csv
    blocks = date_blocks
    return empty_csv if blocks.all? { |b| b[:cars].empty? }

    CSV.generate do |csv|
      csv << header_row(blocks)
      csv << row('Driver') { |car| car.name }
      csv << []
      rider_rows(blocks).each { |r| csv << r }
      csv << []
      csv << total_row(blocks)
      waiting_block(csv, blocks)
    end
  end

  private

  # Every occurrence that day, in time order, each with its own drivers. The
  # board is for one occurrence; the sheet is for the day.
  def date_blocks
    events = Event.active
                  .where(start_time: @board.date.all_day)
                  .includes(rides: %i[user pickup_location])
                  .chronological.to_a
    events = [@board.event] if events.empty?

    events.map do |event|
      board = event.id == @board.event.id ? @board : RideBoard.new(event)
      { event: event, board: board, cars: board.cars }
    end
  end

  # The service name sits over the first of its drivers; the rest of its columns
  # are blank, which is what a merged cell looks like once it is flattened.
  def header_row(blocks)
    cells = [nil]
    blocks.each do |block|
      next if block[:cars].empty?

      cells << title(block[:event])
      cells.concat([nil] * (block[:cars].size - 1))
    end
    cells
  end

  def title(event)
    [event.name, event.start_time&.strftime('%-l:%M %p')].compact_blank.join(' ')
  end

  def row(label, &block)
    [label] + every_car.map(&block)
  end

  # Riders run down the page under their driver. The deepest car sets how many
  # rows there are; every shorter column is padded so the grid stays square.
  def rider_rows(blocks)
    depth = every_car.map { |car| car.passengers.size }.max.to_i
    return [['Riders'] + every_car.map { nil }] if depth.zero?

    (0...depth).map do |i|
      label = i.zero? ? 'Riders' : nil
      # nil, not '' — CSV writes an empty string as a quoted "" and a nil as a
      # genuinely empty cell, which is what a spreadsheet should show.
      [label] + every_car.map { |car| car.passengers[i]&.display_name }
    end
  end

  # One total per service, under the first of its columns — the count of people
  # actually being driven, which is the number the sheet is checked against.
  def total_row(blocks)
    cells = ['Van Total']
    blocks.each do |block|
      next if block[:cars].empty?

      cells << block[:cars].sum { |car| car.passengers.size }
      cells.concat([nil] * (block[:cars].size - 1))
    end
    cells
  end

  # Anyone still without a seat, so the printed sheet says who was missed
  # rather than quietly leaving them off.
  def waiting_block(csv, blocks)
    waiting = blocks.flat_map { |b| b[:board].pool }.uniq(&:id)
    return if waiting.empty?

    csv << []
    csv << ['Still waiting']
    waiting.each { |ride| csv << [nil, ride.display_name, ride.zone.to_s, ride.address.to_s] }
  end

  def every_car
    @every_car ||= date_blocks.flat_map { |block| block[:cars] }
  end

  def empty_csv
    CSV.generate do |csv|
      csv << [nil, title(@board.event)]
      csv << ['Driver']
      csv << []
      csv << ['Riders']
      waiting_block(csv, date_blocks)
    end
  end
end
