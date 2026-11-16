require 'test_helper'

class WorldGeneratorTest < WorldTest
  SX, SY = World::SPAWN

  # ---- the noise functions -------------------------------------------------
  def test_lattice_is_deterministic_and_in_range
    a = World.lattice(3, 4, 'salt')
    assert_equal a, World.lattice(3, 4, 'salt')
    assert_operator a, :>=, 0.0
    assert_operator a, :<=, 1.0
    refute_equal a, World.lattice(3, 4, 'other')
    refute_equal a, World.lattice(4, 3, 'salt')
  end

  def test_noise_stays_in_range_and_is_deterministic
    50.times do |i|
      v = World.noise(i * 7, i * 13, 10, 'n')
      assert_operator v, :>=, 0.0
      assert_operator v, :<=, 1.0
      assert_equal v, World.noise(i * 7, i * 13, 10, 'n')
    end
  end

  def test_noise_is_smooth_between_neighbouring_tiles
    (0..40).each do |i|
      assert_in_delta World.noise(i, 5, 14, 'smooth'), World.noise(i + 1, 5, 14, 'smooth'), 0.25
    end
  end

  def test_elevation_and_moisture_are_within_unit_range
    [[0, 0], [SX, SY], [-5000, 9000], [123_456, -654_321]].each do |x, y|
      [World.elevation(x, y), World.moisture(x, y)].each { |v| assert_includes 0.0..1.0, v }
    end
  end

  # ---- grid positions ------------------------------------------------------
  def test_grid_rounds_coordinates_to_three_decimals
    assert_equal [-79_708, 43_607], World.grid(-79.708, 43.607)
    assert_equal [-79_708, 43_607], World.grid(-79.7081, 43.6069)
    assert_equal [1000, -2500], World.grid('1.0', '-2.5')
  end

  def test_seed_center_matches_the_spawn_grid_position
    assert_equal World::SPAWN, World.grid(*Seed::CENTER)
  end

  # ---- terrain -------------------------------------------------------------
  def test_terrain_is_deterministic
    10.times { |i| assert_equal World.terrain_for(i * 31, i * 17), World.terrain_for(i * 31, i * 17) }
  end

  def test_the_spawn_clearing_is_plain_with_no_buildings
    (-1..1).each do |dx|
      (-1..1).each do |dy|
        assert World.spawn_clearing?(SX + dx, SY + dy)
        assert_equal Plain, World.terrain_for(SX + dx, SY + dy)
        assert_nil World.place_for(Plain, SX + dx, SY + dy)
      end
    end
    refute World.spawn_clearing?(SX + 2, SY)
    refute World.spawn_clearing?(SX, SY - 2)
  end

  def test_land_near_spawn_is_eased_toward_gentle_terrain
    (-8..8).each do |dx|
      (-8..8).each do |dy|
        ix, iy = SX + dx, SY + dy
        e = World.elevation(ix, iy)
        assert_operator (World.friendly_elevation(ix, iy, e) - 0.5).abs, :<=, (e - 0.5).abs + 1e-9
      end
    end
  end

  def test_land_far_from_spawn_is_untouched
    assert_in_delta 0.9, World.friendly_elevation(SX + 40, SY, 0.9), 1e-9
    assert_in_delta 0.1, World.friendly_elevation(SX, SY - 40, 0.1), 1e-9
  end

  def test_the_area_around_spawn_has_variety_and_is_not_all_mountain
    counts = Hash.new(0)
    (-20..20).each { |dx| (-20..20).each { |dy| counts[World.terrain_for(SX + dx, SY + dy).name] += 1 } }
    total = counts.values.sum
    assert_operator counts.keys.size, :>=, 3
    assert_operator counts['Mountain'].to_f / total, :<, 0.25
    assert_operator (counts['Plain'] + counts['Forest']).to_f / total, :>, 0.3
  end

  def test_every_terrain_that_can_be_produced_is_a_known_location_class
    (-30..30).step(3) do |dx|
      (-30..30).step(3) do |dy|
        assert_operator World.terrain_for(SX + dx, SY + dy), :<=, Location
      end
    end
  end

  # ---- buildings -----------------------------------------------------------
  def test_every_building_named_in_the_table_exists_as_a_class
    World::PLACES.each_value do |names|
      names.each { |n| assert Object.const_defined?(n), "#{n} is not defined" }
    end
  end

  def test_water_never_gets_buildings
    (0..300).each do |i|
      assert_nil World.place_for(Sea, i, i * 3)
      assert_nil World.place_for(Lake, i * 2, i)
    end
  end

  def test_buildings_appear_on_roughly_the_expected_share_of_tiles
    built = 0
    n = 0
    (-40..40).each do |dx|
      (-40..40).each do |dy|
        ix, iy = SX + dx + 100, SY + dy + 100 # away from the spawn clearing
        built += 1 if World.place_for(World.terrain_for(ix, iy), ix, iy)
        n += 1
      end
    end
    ratio = built.to_f / n
    assert_operator ratio, :>, 0.01
    assert_operator ratio, :<, 0.12
  end

  def test_building_choice_is_deterministic_and_suits_the_terrain
    (-40..40).each do |dx|
      ix, iy = SX + 100 + dx, SY + 100
      t = World.terrain_for(ix, iy)
      b = World.place_for(t, ix, iy)
      again = World.place_for(t, ix, iy)
      b.nil? ? assert_nil(again) : assert_equal(b, again)
      assert_includes World::PLACES.fetch(t.name), b.name if b
    end
  end

  # ---- ensure_area ---------------------------------------------------------
  def test_ensure_area_creates_a_square_of_tiles
    assert_equal 25, World.ensure_area(*Seed::CENTER, 2)
    assert_equal 25, Location.count
  end

  def test_ensure_area_is_idempotent
    World.ensure_area(*Seed::CENTER, 2)
    assert_equal 0, World.ensure_area(*Seed::CENTER, 2)
    assert_equal 25, Location.count
  end

  def test_growing_the_area_only_adds_the_missing_tiles
    World.ensure_area(*Seed::CENTER, 1)
    assert_equal 25 - 9, World.ensure_area(*Seed::CENTER, 2)
    assert_equal 25, Location.count
  end

  def test_radius_zero_is_a_single_tile_and_negative_radius_is_too
    assert_equal 1, World.ensure_area(*Seed::CENTER, 0)
    assert_equal 0, World.ensure_area(*Seed::CENTER, -4)
    assert_equal 1, Location.count
  end

  def test_radius_is_capped_so_one_call_cannot_flood_the_database
    World.ensure_area(*Seed::CENTER, 500)
    side = 2 * World::MAX_RADIUS + 1
    assert_equal side * side, Location.count
  end

  def test_created_tiles_have_distinct_grid_positions_and_use_the_generator_terrain
    World.ensure_area(*Seed::CENTER, 3)
    seen = {}
    Location.all.each do |tile|
      key = World.grid(tile.cx, tile.cy)
      refute seen[key], "duplicate tile at #{key.inspect}"
      seen[key] = true
      assert_equal World.terrain_for(*key), tile.class
    end
  end

  def test_tile_at_finds_the_tile_and_misses_elsewhere
    World.ensure_area(*Seed::CENTER, 1)
    tile = World.tile_at(*Seed::CENTER)
    assert_equal Plain, tile.class
    assert_nil World.tile_at(10.0, 10.0)
  end

  def test_buildings_are_created_with_their_tiles
    World.ensure_area(*Seed::CENTER, 12)
    assert_operator Place.count, :>, 0
    Place.all.each { |p| assert_includes World::PLACES.fetch(p.location.class.name), p.class.name }
  end

  def test_tiles_from_an_older_map_get_the_buildings_the_generator_says_they_should
    ix, iy, building = nil
    (1..400).each do |dx|
      iy0 = SY + 50
      t = World.terrain_for(SX + dx, iy0)
      b = World.place_for(t, SX + dx, iy0)
      if b then ix, iy, building = SX + dx, iy0, b; break end
    end
    skip 'no building position found in the scan' unless ix
    terrain = World.terrain_for(ix, iy)
    terrain.create(cx: ix / 1000.0, cy: iy / 1000.0) # a tile with no building, as old maps had
    assert_equal 0, Place.count
    World.ensure_area(ix / 1000.0, iy / 1000.0, 0)
    assert_equal 1, Place.count
    assert_equal building, Place.first.class
  end

  # ---- preload_places ------------------------------------------------------
  def test_preload_places_attaches_each_tiles_buildings_with_their_real_class
    World.ensure_area(*Seed::CENTER, 12)
    tiles = Location.all.to_a
    World.preload_places(tiles)
    built = tiles.select { |t| t.buildings.any? }
    assert_operator built.size, :>, 0
    built.each { |t| t.buildings.each { |p| assert_operator p.class, :<, Place } }
    assert_equal Place.count, tiles.sum { |t| t.buildings.size }
  end

  def test_preload_places_with_no_tiles_is_a_no_op
    assert_equal [], World.preload_places([])
  end
end
