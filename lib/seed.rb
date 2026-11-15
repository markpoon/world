# Demo data. Explicit and idempotent: safe to run on every boot.
#
# The login screen says "Demo: no email or password" and the browser code then
# sends DEMO_EMAIL / DEMO_PASSWORD's defaults below, so leaving both fields
# blank logs in as the demo user. Override with env vars if you want others.
module Seed
  DEMO_EMAIL    = ENV.fetch('DEMO_EMAIL', 'markpoon@me.com')
  DEMO_PASSWORD = ENV.fetch('DEMO_PASSWORD', 'some phrase')
  # where the browser client centers its map (root.center in views/script.coffee)
  CENTER = [-79.708, 43.607]
  RADIUS = 5 # tiles in each direction; matches a user's default vision

  # a small hand-made starting map, since WorldFactory needs the Overpass API
  def self.terrain_for(x, y)
    return Plain if x.abs <= 1 && y.abs <= 1 # keep the start tile safe to walk on
    case (x * 7 + y * 13) % 11
    when 0, 1 then Forest
    when 2    then Hill
    when 3    then Lake
    else Plain
    end
  end

  def self.starting_map!
    (-RADIUS..RADIUS).each do |x|
      (-RADIUS..RADIUS).each do |y|
        coordinates = [(CENTER[0] + x * 0.001).round(3), (CENTER[1] + y * 0.001).round(3)]
        next if Location.first(cx: coordinates[0], cy: coordinates[1])
        terrain_for(x, y).create(coordinates: coordinates)
      end
    end
  end

  def self.demo_user!
    existing = User.first(email: DEMO_EMAIL)
    return existing if existing
    starting_map!
    user = User.new(email: DEMO_EMAIL, password: DEMO_PASSWORD)
    user.location = Location.first(cx: CENTER[0].round(3), cy: CENTER[1].round(3))
    user.save
    puts "Seed: created demo user #{DEMO_EMAIL} (#{Location.count} locations, #{Character.count} characters)"
    user
  end
end
