# Demo data. Explicit and idempotent: safe to run on every boot.
#
# The login screen says "Demo: no email or password" and the browser code then
# sends DEMO_EMAIL / DEMO_PASSWORD's defaults below, so leaving both fields
# blank logs in as the demo user. Override with env vars if you want others.
module Seed
  DEMO_EMAIL    = ENV.fetch('DEMO_EMAIL', 'markpoon@me.com')
  DEMO_PASSWORD = ENV.fetch('DEMO_PASSWORD', 'some phrase')
  # where the browser client centers its map (root.center in views/script.coffee)
  CENTER = [World::SPAWN[0] / World::SCALE.to_f, World::SPAWN[1] / World::SCALE.to_f]
  RADIUS = 6 # tiles in each direction (a user sees 5 by default)

  def self.starting_map!
    World.ensure_area(*CENTER, RADIUS)
  end

  def self.demo_user!
    existing = User.first(email: DEMO_EMAIL)
    return existing if existing
    starting_map!
    user = User.new(email: DEMO_EMAIL, password: DEMO_PASSWORD)
    user.location = World.tile_at(*CENTER)
    user.save
    puts "Seed: created demo user #{DEMO_EMAIL} (#{Location.count} locations, #{Character.count} characters)"
    user
  end
end
