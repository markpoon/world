# Gameplay smoke test: creates and serialises each kind of record against a
# throwaway SQLite database and reports what works. Run from the repo root:
#   RACK_ENV=development DATABASE_URL=sqlite3:///tmp/smoke.db ruby tools/smoke.rb
require './lib/app_env'
require 'bundler'; Bundler.require(:default, :development)
require 'sinatra/base'; require 'json'; require 'bigdecimal'; require 'set'; require 'timeout'
require './modules'; require 'data_mapper'
require './lib/game_model'; require './models/models.rb'
require './lib/world_generator'; require './lib/seed'; require './controllers/controllers.rb'
DataMapper.setup(:default, ENV['DATABASE_URL'] || 'sqlite3:///tmp/smoke.db')
DataMapper.finalize.auto_upgrade!

$results = []
def check(name)
  r = Timeout.timeout(8) { yield }
  $results << [name, true, nil]
rescue Exception => e # rubocop:disable Lint/RescueException (Timeout is an Exception)
  $results << [name, false, "#{e.class}: #{e.message.lines.first.to_s.strip} (#{e.backtrace.find { |l| l.include?('/world/') && !l.include?('vendor') }.to_s.sub(Dir.pwd + '/', '')})"]
end

user = nil
check('seed demo user')            { user = Seed.demo_user! or raise 'nil' }
check('login (authenticate)')      { User.authenticate(Seed::DEMO_EMAIL, Seed::DEMO_PASSWORD) or raise 'rejected' }
check('user.sight as json')        { JSON.parse(user.sight.to_json).fetch('locations').size > 0 or raise 'empty' }
check('user validation rejects blank') { u = User.new(email: '', password: 'x'); raise 'saved' if u.save }
check('user validation rejects bad email') { u = User.new(email: 'nope', password: 'longenough'); u.location = loc0 = World.tile_at(*Seed::CENTER); raise 'saved' if u.save }
ch = nil
check('character exists')          { ch = user.characters.first or raise 'none' }
check('character as_json')         { ch.as_json.to_json }
check('character stats/check')     { ch.check(:strength); ch.scratch; ch.energy; ch.wound_max }
check('character name/gender')     { ch.name; ch.gender }
check('character holdings')        { ch.holdings.to_a }
check('character items')           { ch.items.to_a }
loc = World.tile_at(*Seed::CENTER)
check('location as_json')          { loc.as_json.to_json }
check('location buildings')        { loc.buildings.to_a }
check('within_circle')             { Location.within(loc.coordinates, 0.01).to_a.size > 0 or raise 'none' }
%w[Farm Shack House Inn Smith Hall Market Academy Fortress Stockpile].each do |name|
  next unless Object.const_defined?(name)
  klass = Object.const_get(name)
  check("place #{klass}") { p = klass.new(location: loc); p.save; p.as_json.to_json; p.name }
end
%w[Sword Axe Dagger Bow LeatherArmor Ring Potion Key].each do |name|
  klass = Object.const_get(name)
  check("item #{klass}") { i = klass.new; i.save; i.as_json.to_json; i.name; i.price; i.portrait }
end
check('item equip')                { s = Sword.new; s.save; ch.items << s; ch.save; s.equip if s.respond_to?(:equip) }
check('inventory carry')           { ch.send(:carry) }
check('family create')             { f = Family.new(name: 'Test'); f.save; f.fullname }
check('faction create')            { f = Faction.new; f.save; f.name }
check('event create')              { e = Event.new; e.save }
check('Logging event')             { e = Logging.new(location: loc); e.save; e.to_s }
check('Travellers event')          { e = Travellers.new(location: loc); e.save; e.to_s }
check('journey create')            { j = Journey.new; j.save }
check('ability create')            { a = Ability.new; a.save; a.as_json }
check('sector create')             { s = Sector.new; s.save }

width = $results.map { |r| r[0].size }.max
$results.each { |n, ok, msg| puts "#{ok ? 'ok  ' : 'FAIL'} #{n.ljust(width)} #{msg}" }
puts "\n#{$results.count { |r| r[1] }}/#{$results.size} passed"
exit!($results.all? { |r| r[1] } ? 0 : 1) # skip Sinatra's at_exit auto-run server
