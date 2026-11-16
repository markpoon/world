# Optional clean-up after upgrading a database that was created by the old
# (Mongoid-style) code. The columns below are no longer used: ids that used to be
# stored as JSON arrays are now real join tables, and a few columns were renamed.
#
# It only drops a column when every row is empty; anything that still holds data
# is reported and left alone. Safe to run more than once.
#
#   DATABASE_URL=postgres://... bundle exec ruby tools/drop_legacy_columns.rb          # dry run
#   DATABASE_URL=postgres://... bundle exec ruby tools/drop_legacy_columns.rb --drop   # do it
require 'bundler/setup'
require 'data_mapper'
url = ENV.fetch('DATABASE_URL').sub(/\Apostgresql:/, 'postgres:')
require(url.start_with?('postgres') ? 'dm-postgres-adapter' : 'dm-sqlite-adapter')

LEGACY = {
  'chapters'   => %w[e],
  'events'     => %w[c target journey_ids],
  'factions'   => %w[sector_ids],
  'items'      => %w[ability_ids lodging_id market_id refinery_id],
  'journeys'   => %w[character_ids event_ids objective_ids sector_ids],
  'objectives' => %w[a e j],
  'sectors'    => %w[faction_ids],
  'stats'      => %w[ability_ids journey_ids progenitor_ids progeny_ids],
  'tasks'      => %w[c d target task_id]
}.freeze

drop = ARGV.include?('--drop')
DataMapper.setup(:default, url)
adapter = DataMapper.repository.adapter
q = ->(name) { adapter.send(:quote_name, name) }

LEGACY.each do |table, columns|
  existing = adapter.select("SELECT column_name FROM information_schema.columns WHERE table_name = '#{table}'")
  columns.each do |column|
    next unless existing.include?(column)
    used = adapter.select("SELECT COUNT(*) FROM #{q.(table)} WHERE #{q.(column)} IS NOT NULL AND CAST(#{q.(column)} AS TEXT) NOT IN ('', '[]', '{}')").first
    if used.to_i > 0
      puts "keep   #{table}.#{column} (#{used} rows still have data)"
    elsif drop
      adapter.execute("ALTER TABLE #{q.(table)} DROP COLUMN #{q.(column)}")
      puts "dropped #{table}.#{column}"
    else
      puts "unused #{table}.#{column} (run with --drop to remove)"
    end
  end
end
