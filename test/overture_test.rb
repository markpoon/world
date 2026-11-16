require 'test_helper'
require 'zlib'
require 'csv'

# Real places from Overture Maps become buildings, and the world fills in the
# squares next to the player as they walk.
class OvertureTest < WorldTest
  include Rack::Test::Methods
  def app; APP; end

  SX, SY = World::SPAWN
  HEADER = %w[id name category group taxonomy confidence lng lat].freeze

  # Write a small data file (csv.gz + json) like tools/fetch_overture.py does.
  # `rows` are [id, name, category, group, confidence, ix, iy] on the tile grid.
  def write_data(rows, name: 'test', release: '2026-01-01.0', box: nil)
    dir = Dir.mktmpdir('overture')
    (@dirs ||= []) << dir
    file = File.join(dir, "#{name}.csv.gz")
    Zlib::GzipWriter.open(file) do |gz|
      csv = CSV.new(gz)
      csv << HEADER
      rows.each do |id, title, category, group, confidence, ix, iy|
        csv << [id, title, category, group, category, confidence, ix / 1000.0, iy / 1000.0]
      end
    end
    box ||= [(SX - 40) / 1000.0, (SY - 40) / 1000.0, (SX + 40) / 1000.0, (SY + 40) / 1000.0]
    File.write(File.join(dir, "#{name}.json"),
               { name: name, release: release, west: box[0], south: box[1], east: box[2], north: box[3] }.to_json)
    file
  end

  def teardown; (@dirs || []).each { |d| FileUtils.rm_rf(d) }; end

  def tile(ix, iy); World.tile_at(ix / 1000.0, iy / 1000.0); end
  def buildings_on(ix, iy); (t = tile(ix, iy)) ? t.buildings : []; end

  # ---- category -> building --------------------------------------------------
  def test_categories_become_buildings
    {
      %w[restaurant food_and_drink] => 'Inn', %w[coffee_shop food_and_drink] => 'Inn', %w[hotel lodging] => 'Inn',
      %w[hardware_home_and_garden_store shopping] => 'Market', %w[pharmacy_and_drug_store shopping] => 'Market',
      %w[automotive_service travel_and_transportation] => 'Blacksmith', %w[manufacturer services_and_business] => 'Blacksmith',
      %w[real_estate_service services_and_business] => 'House', %w[home_service services_and_business] => 'House',
      %w[christian_place_of_worship community_and_government] => 'Hall', %w[bank_or_credit_union services_and_business] => 'Hall',
      %w[park sports_and_recreation] => 'Pasture', %w[animal_or_pet_service lifestyle_services] => 'Pasture',
      %w[historic_site cultural_and_historic] => 'Castle', %w[gym sports_and_recreation] => 'Barrack',
      %w[storage_facility services_and_business] => 'Mill', %w[quarry services_and_business] => 'Mine',
      %w[farm services_and_business] => 'Farm', %w[personal_or_beauty_service lifestyle_services] => 'Shack'
    }.each do |(category, section), building|
      assert_equal building, Overture.building_for(category, section), "#{category} should be a #{building}"
    end
  end

  def test_parking_is_not_a_park_and_a_coffee_shop_is_not_a_shop
    refute_equal 'Pasture', Overture.building_for('parking', 'travel_and_transportation')
    assert_equal 'Inn', Overture.building_for('coffee_shop', 'food_and_drink')
  end

  def test_unknown_categories_fall_back_to_the_section_then_to_a_shack
    assert_equal 'Hall', Overture.building_for('something_new', 'community_and_government')
    assert_equal 'Shack', Overture.building_for('something_new', 'unheard_of')
    assert_equal 'Shack', Overture.building_for(nil, nil)
  end

  def test_every_building_the_importer_can_produce_is_a_real_place_class
    names = Overture::RULES.map(&:first) + Overture::SECTION_BUILDINGS.values + [Overture::FALLBACK]
    names.uniq.each { |n| assert Object.const_get(n) <= Place, "#{n} must be a Place" }
  end

  # ---- loading ------------------------------------------------------------------
  def test_loading_a_file_stores_places_and_the_region_they_cover
    file = write_data([['a', 'Joe Coffee', 'coffee_shop', 'food_and_drink', 0.9, SX + 5, SY],
                       ['b', 'Bank', 'bank_or_credit_union', 'services_and_business', 0.8, SX + 6, SY]])
    region = Overture.load_file(file)
    assert_equal 2, PointOfInterest.count
    assert_equal 2, region.places
    assert_equal '2026-01-01.0', region.release
    poi = PointOfInterest.first(overture_id: 'a')
    assert_equal 'Joe Coffee', poi.name
    assert_equal 'Inn', poi.building
    assert_equal [SX + 5, SY + 0], [poi.ix, poi.iy]
  end

  def test_names_with_accents_and_other_alphabets_survive_loading
    Overture.load_file(write_data([['a', "Caf\u00e9 Z\u00fcrich \u4e2d\u6587", 'cafe', 'food_and_drink', 0.5, SX + 5, SY]]))
    assert_equal "Caf\u00e9 Z\u00fcrich \u4e2d\u6587", PointOfInterest.first.name
  end

  def test_loading_the_same_release_twice_does_nothing
    file = write_data([['a', 'A', 'cafe', 'food_and_drink', 0.5, SX + 5, SY]])
    assert Overture.load_file(file)
    assert_nil Overture.load_file(file)
    assert_equal 1, PointOfInterest.count
  end

  def test_a_newer_release_replaces_the_old_one
    Overture.load_file(write_data([['old', 'Old', 'cafe', 'food_and_drink', 0.5, SX + 5, SY]]))
    Overture.load_file(write_data([['new', 'New', 'cafe', 'food_and_drink', 0.5, SX + 5, SY]], release: '2026-02-01.0'))
    assert_equal ['new'], PointOfInterest.all.map(&:overture_id)
    assert_equal 1, PoiRegion.count
  end

  def test_load_bundled_loads_every_file_in_the_folder
    dir = Dir.mktmpdir('overture'); (@dirs ||= []) << dir
    %w[one two].each_with_index do |n, i|
      f = write_data([["#{n}1", n, 'cafe', 'food_and_drink', 0.5, SX + 5 + i, SY]], name: n)
      FileUtils.cp([f, f.sub('.csv.gz', '.json')], dir)
    end
    assert_equal 2, Overture.load_bundled!(dir).size
    assert_equal 2, PointOfInterest.count
    assert_empty Overture.load_bundled!(dir)
  end

  def test_the_bundled_mississauga_file_covers_the_spawn_area
    meta = JSON.parse(File.read(File.join(Overture::DATA_DIR, 'mississauga.json')))
    assert_operator meta['west'], :<, SX / 1000.0
    assert_operator meta['east'], :>, SX / 1000.0
    assert_operator meta['rows'], :>, 1000
    assert File.exist?(File.join(Overture::DATA_DIR, 'mississauga.csv.gz'))
  end

  # ---- the map --------------------------------------------------------------------
  def test_a_real_place_becomes_a_building_on_its_tile
    Overture.load_file(write_data([['a', 'Joe Coffee', 'coffee_shop', 'food_and_drink', 0.9, SX + 4, SY + 3]]))
    World.ensure_area(*Seed::CENTER, 6)
    building = buildings_on(SX + 4, SY + 3).first
    assert_kind_of Inn, building
    assert_equal 'Joe Coffee', building.title
    assert_equal 'coffee_shop', building.category
    assert_equal 'overture', building.source
    assert_equal 'a', building.source_id
  end

  def test_the_most_trusted_place_wins_a_busy_tile
    Overture.load_file(write_data([['low', 'Low', 'bank_or_credit_union', 'services_and_business', 0.2, SX + 4, SY + 3],
                                   ['high', 'High', 'restaurant', 'food_and_drink', 0.95, SX + 4, SY + 3],
                                   ['mid', 'Mid', 'park', 'sports_and_recreation', 0.5, SX + 4, SY + 3]]))
    World.ensure_area(*Seed::CENTER, 6)
    buildings = buildings_on(SX + 4, SY + 3)
    assert_equal 1, buildings.size
    assert_equal 'High', buildings.first.title
  end

  def test_the_building_json_carries_the_real_name_and_category
    Overture.load_file(write_data([['a', 'Joe Coffee', 'coffee_shop', 'food_and_drink', 0.9, SX + 4, SY + 3]]))
    World.ensure_area(*Seed::CENTER, 6)
    json = buildings_on(SX + 4, SY + 3).first.as_json
    assert_equal 'Joe Coffee', json['title']
    assert_equal 'coffee_shop', json['category']
    assert_equal 'Inn', json['_type']
  end

  def test_inside_a_data_region_tiles_without_a_real_place_stay_empty
    World.ensure_area(*Seed::CENTER, 12)
    assert_operator Place.count, :>, 0, 'the generator invented some buildings first'
    Overture.load_file(write_data([['a', 'Joe', 'cafe', 'food_and_drink', 0.9, SX + 4, SY + 3]]))
    World.ensure_area(*Seed::CENTER, 12) # existing tiles are brought in line with the data
    assert_equal ['a'], Place.all.map(&:source_id), 'invented buildings are removed inside real-data regions'
  end

  def test_outside_a_data_region_the_generator_still_invents_buildings
    Overture.load_file(write_data([['a', 'Joe', 'cafe', 'food_and_drink', 0.9, SX + 4, SY + 3]]))
    World.ensure_area((SX + 300) / 1000.0, (SY + 300) / 1000.0, 12)
    assert_operator Place.count, :>, 0
    assert Place.all.all? { |p| p.source.nil? }
  end

  def test_new_tiles_in_a_data_region_get_only_real_places
    Overture.load_file(write_data([]))
    World.ensure_area(*Seed::CENTER, 12)
    assert_operator Location.count, :>, 500
    assert_equal 0, Place.count
  end

  def test_the_spawn_clearing_is_never_built_on
    Overture.load_file(write_data([['a', 'Joe', 'cafe', 'food_and_drink', 0.9, SX, SY]]))
    World.ensure_area(*Seed::CENTER, 3)
    assert_empty buildings_on(SX, SY)
  end

  def test_a_real_place_in_the_sea_is_moved_onto_land
    ix, iy = (1..400).map { |i| [SX + 80 + i, SY + 80] }.find { |x, y| World.terrain_for(x, y) <= Sea }
    skip 'no sea tile found' unless ix
    box = [ix / 1000.0 - 0.01, iy / 1000.0 - 0.01, ix / 1000.0 + 0.01, iy / 1000.0 + 0.01]
    Overture.load_file(write_data([['a', 'Pier', 'cafe', 'food_and_drink', 0.9, ix, iy]], box: box))
    World.ensure_area(ix / 1000.0, iy / 1000.0, 1)
    assert_kind_of Plain, tile(ix, iy)
    assert_equal 'Pier', buildings_on(ix, iy).first.title
  end

  def test_building_real_places_is_repeatable
    Overture.load_file(write_data([['a', 'Joe', 'cafe', 'food_and_drink', 0.9, SX + 4, SY + 3]]))
    World.ensure_area(*Seed::CENTER, 6)
    count = [Location.count, Place.count]
    assert_equal 0, World.ensure_area(*Seed::CENTER, 6)
    assert_equal count, [Location.count, Place.count]
  end

  # ---- walking: populate_adjacent ---------------------------------------------------
  def test_stepping_next_to_unbuilt_ground_builds_the_adjacent_squares
    assert_equal 0, Location.count
    result = World.populate_adjacent(*Seed::CENTER, 1)
    assert_equal 9, result[:created]
    assert_equal 9, result[:tiles].size
  end

  def test_only_the_missing_squares_are_built
    World.ensure_area(*Seed::CENTER, 1)
    step_east = [(SX + 1) / 1000.0, SY / 1000.0]
    result = World.populate_adjacent(*step_east, 1)
    assert_equal 3, result[:created], 'one new column of three'
    assert_equal 9, result[:tiles].size
    assert_equal 0, World.populate_adjacent(*step_east, 1)[:created]
  end

  def test_reach_is_limited_to_a_few_squares
    assert_equal 49, World.populate_adjacent(*Seed::CENTER, 99)[:tiles].size # 7 x 7 at most
    assert_equal 9,  World.populate_adjacent(*Seed::CENTER, 0)[:tiles].size  # at least the neighbours
  end

  def test_adjacent_squares_far_from_the_start_still_get_buildings_from_real_data
    Overture.load_file(write_data([['a', 'Joe', 'cafe', 'food_and_drink', 0.9, SX + 31, SY + 30]],
                                  box: [(SX + 20) / 1000.0, (SY + 20) / 1000.0, (SX + 40) / 1000.0, (SY + 40) / 1000.0]))
    World.populate_adjacent((SX + 30) / 1000.0, (SY + 30) / 1000.0, 1)
    assert_equal 'Joe', buildings_on(SX + 31, SY + 30).first.title
  end

  def test_populated_tiles_are_ready_to_send_with_their_buildings
    Overture.load_file(write_data([['a', 'Joe', 'cafe', 'food_and_drink', 0.9, SX + 4, SY + 3]]))
    tiles = World.populate_adjacent((SX + 3) / 1000.0, (SY + 3) / 1000.0, 1)[:tiles]
    with_place = tiles.select { |t| t.as_json['places'] }
    assert_equal 1, with_place.size
    assert_equal 'Joe', with_place.first.as_json['places'].first['title']
  end

  # ---- the HTTP endpoint -------------------------------------------------------------
  def login!
    make_user('walker@example.com', 'a good passphrase')
    authorize 'walker@example.com', 'a good passphrase'
    capture_io { get '/user/login' }
    assert_equal 200, last_response.status
  end

  def test_explore_requires_a_login
    get '/user/explore', lng: SX / 1000.0, lat: SY / 1000.0
    assert_equal 401, last_response.status
  end

  def test_explore_builds_and_returns_the_squares_around_the_given_tile
    login!
    step = [(SX + 9) / 1000.0, (SY + 9) / 1000.0] # past the 6-tile map made at login
    get '/user/explore', lng: step[0], lat: step[1], reach: 1
    assert_equal 200, last_response.status
    body = JSON.parse(last_response.body)
    assert_equal 9, body['created']
    assert_equal 9, body['locations'].size
    assert body['locations'].all? { |l| l['c'] && l['_type'] }
    get '/user/explore', lng: step[0], lat: step[1], reach: 1
    assert_equal 0, JSON.parse(last_response.body)['created']
  end

  def test_explore_rejects_bad_or_far_away_requests
    login!
    get '/user/explore'
    assert_equal 400, last_response.status
    get '/user/explore', lng: 'x', lat: 'y'
    assert_equal 400, last_response.status
    get '/user/explore', lng: SX / 1000.0 + 5, lat: SY / 1000.0
    assert_equal 400, last_response.status
  end

  def test_explore_limits_the_reach
    login!
    get '/user/explore', lng: (SX + 12) / 1000.0, lat: SY / 1000.0, reach: 50
    assert_equal 49, JSON.parse(last_response.body)['locations'].size
  end
end
