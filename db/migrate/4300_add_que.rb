# que's job table, functions and triggers (schema version 7, que 2.x).
#
# Note: db/schema.rb is Ruby-format and cannot represent que's functions and
# triggers, so a database built with db:schema:load would have the table but
# not the machinery. Build databases with db:migrate (as test_setup and the
# installer already do).
class AddQue < ActiveRecord::Migration[8.0]
  def up
    require 'que'
    Que.connection = ::ActiveRecord
    Que.migrate!(version: 7)
  end

  def down
    require 'que'
    Que.connection = ::ActiveRecord
    Que.migrate!(version: 0)
  end
end
