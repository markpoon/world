require 'test_helper'
require 'zlib'
require 'csv'

# Finding out where a player is, and fetching the real places around them while
# the app runs. Nothing here touches the network: the fetcher and the IP lookup
# are replaced by fakes.
class LiveRegionTest < WorldTest
  include Rack::Test::Methods
  def app; APP; end

  SX, SY = World::SPAWN
  TORONTO = [-79.383, 43.653].freeze   # a long way from the default start
  LONDON  = [-0.128, 51.507].freeze

  # A fake fetcher: writes a csv.gz with one cafe in the middle of the box it is asked for.
  class FakeFetcher
    attr_reader :calls
    def initialize(places: 1, fail: false, around: nil); @places = places; @fail = fail; @around = around; @calls = []; end

    def call(name, west, south, east, north, release)
      @calls << [name, west, south, east, north, release]
      raise Overture::Fetcher::Error, 'network down' if @fail
      dir = Dir.mktmpdir('fake-overture')
      file = File.join(dir, "#{name}.csv.gz")
      Zlib::GzipWriter.open(file) do |gz|
        csv = CSV.new(gz)
        csv << %w[id name category group taxonomy confidence lng lat]
        @places.times do |n|
          csv << ["#{name}-#{n}", "Cafe #{n}", 'cafe', 'food_and_drink', 'cafe', 0.9,
                  ((@around ? @around[0] : (west + east) / 2) + (n - @places / 2) * 0.001).round(6),
                  (@around ? @around[1] + 0.005 : (south + north) / 2)]
        end
      end
      file
    end
  end

  def live(fetcher = FakeFetcher.new, inline: true)
    Overture::Regions.fetcher = fetcher
    Overture::Regions.inline = inline
    fetcher
  end

  def with_live(&block); with_env('OVERTURE_LIVE' => 'true', &block); end
  def with_geoip(&block); with_env('GEOIP' => 'true', &block); end

  # ---- cells ----------------------------------------------------------------------
  def test_the_world_is_cut_into_fixed_cells
    assert_equal [-798, 436], Overture::Regions.cell(-79.708, 43.607)
    assert_equal [-798, 436], Overture::Regions.cell(-79.75, 43.69)
    assert_equal [-797, 436], Overture::Regions.cell(-79.69, 43.61)
    assert_equal [-80.0, 43.0, -79.9, 43.1], Overture::Regions.box(-800, 430)
  end

  # ---- requesting -------------------------------------------------------------------
  def test_a_requested_cell_is_fetched_loaded_and_then_ready
    with_live do
      fetcher = live
      assert_equal :idle, Overture::Regions.status(*TORONTO)
      assert_equal :ready, Overture::Regions.request(*TORONTO)
      assert_equal :ready, Overture::Regions.status(*TORONTO)
      name, west, south, east, north, = fetcher.calls.first
      assert_equal 'cell_-794_436', name
      assert_operator west, :<=, TORONTO[0]
      assert_operator east, :>=, TORONTO[0]
      assert_operator south, :<=, TORONTO[1]
      assert_operator north, :>=, TORONTO[1]
      assert_equal 1, PointOfInterest.count
      assert_equal 1, PoiRegion.count
    end
  end

  def test_asking_again_does_not_fetch_again
    with_live do
      fetcher = live
      2.times { Overture::Regions.request(*TORONTO) }
      assert_equal 1, fetcher.calls.size
    end
  end

  def test_the_bundled_area_needs_no_fetch
    with_live do
      fetcher = live
      Overture.load_bundled!
      assert_equal :ready, Overture::Regions.request(*Seed::CENTER)
      assert_empty fetcher.calls
    end
  end

  def test_nothing_is_fetched_when_the_feature_is_off
    with_env('OVERTURE_LIVE' => 'false') do
      fetcher = live
      assert_equal :unavailable, Overture::Regions.request(*TORONTO)
      assert_empty fetcher.calls
    end
  end

  def test_without_python_and_duckdb_the_feature_reports_unavailable
    with_live do
      with_env('PYTHON' => '/nonexistent/python3') do
        Overture::Fetcher.reset!
        assert_equal :unavailable, Overture::Regions.request(*TORONTO)
      end
      Overture::Fetcher.reset!
    end
  end

  def test_a_failed_fetch_is_reported_and_not_retried_straight_away
    with_live do
      fetcher = live(FakeFetcher.new(fail: true))
      capture_io { assert_equal :failed, Overture::Regions.request(*TORONTO) }
      assert_equal :failed, Overture::Regions.status(*TORONTO)
      assert_equal :failed, Overture::Regions.request(*TORONTO)
      assert_equal 1, fetcher.calls.size
      assert_equal 0, PoiRegion.count
    end
  end

  def test_a_failed_fetch_may_be_tried_again_after_a_while
    with_live do
      fetcher = live(FakeFetcher.new(fail: true))
      capture_io { Overture::Regions.request(*TORONTO) }
      jobs = Overture::Regions.instance_variable_get(:@jobs)
      jobs.values.each { |j| j[:at] = Time.now - Overture::Regions::RETRY_AFTER - 1 }
      capture_io { Overture::Regions.request(*TORONTO) }
      assert_equal 2, fetcher.calls.size
    end
  end

  def test_a_cell_with_few_places_is_sparse_so_the_generator_fills_the_gaps
    with_live do
      live(FakeFetcher.new(places: 3))
      Overture::Regions.request(*TORONTO)
      assert PoiRegion.first.sparse
    end
  end

  def test_a_well_mapped_cell_is_not_sparse
    with_live do
      live(FakeFetcher.new(places: Overture::Regions::SPARSE_BELOW + 5))
      Overture::Regions.request(*TORONTO)
      refute PoiRegion.first.sparse
    end
  end

  def test_sparse_cells_keep_invented_buildings_between_the_real_ones
    with_live do
      live(FakeFetcher.new(places: 1, around: TORONTO))
      Overture::Regions.request(*TORONTO)
    end
    World.ensure_start(*TORONTO)
    generated = Place.all.select { |p| p.source.nil? }
    real = Place.all.select { |p| p.source == 'overture' }
    assert_operator generated.size, :>, 0
    assert_equal 1, real.size
  end

  def test_a_cell_near_an_edge_also_fetches_its_neighbour
    with_live do
      fetcher = live
      edge = [-79.4 - 0.002, 43.65] # 0.002 degrees from the cell boundary at -79.4
      Overture::Regions.request(*edge)
      assert_equal %w[cell_-794_436 cell_-795_436], fetcher.calls.map(&:first).sort
    end
  end

  def test_each_requester_has_an_hourly_limit
    with_live do
      fetcher = live
      limit = Overture::Regions::PER_REQUESTER_PER_HOUR
      results = (0..limit).map { |n| Overture::Regions.request(-70.05 + n * 0.5, 40.05, '1.2.3.4') }
      assert_equal :limited, results.last
      assert_equal limit, fetcher.calls.size
      assert_equal :ready, Overture::Regions.request(-50.05, 40.05, '5.6.7.8'), 'another requester is not affected'
    end
  end

  def test_there_is_a_daily_limit_on_downloads
    with_live do
      with_env('OVERTURE_MAX_CELLS_PER_DAY' => '2') do
        live
        results = 3.times.map { |n| Overture::Regions.request(-70.05 + n * 0.5, 40.05) }
        assert_equal %i[ready ready limited], results
      end
    end
  end

  def test_background_fetching_runs_in_a_thread_and_finishes
    with_live do
      live(FakeFetcher.new, inline: false)
      status = Overture::Regions.request(*TORONTO)
      assert_includes %i[loading ready], status
      Overture::Regions.wait_idle
      assert_equal :ready, Overture::Regions.status(*TORONTO)
      assert_equal 1, PoiRegion.count
    end
  end

  # ---- a new place on the map ----------------------------------------------------------
  def test_a_start_anywhere_in_the_world_is_walkable_land
    [TORONTO, LONDON, [151.209, -33.868], [-43.2, -22.9], [139.69, 35.69]].each do |lng, lat|
      tile = World.ensure_start(lng, lat)
      refute_nil tile
      refute_includes %w[Sea Lake Mountain], tile.class.name, "start at #{lng},#{lat}"
      ix, iy = World.grid(lng, lat)
      (-1..1).each do |dx|
        (-1..1).each do |dy|
          t = World.tile_at((ix + dx) / 1000.0, (iy + dy) / 1000.0)
          assert_kind_of Plain, t, 'the 3x3 around a start is open plains'
          assert_empty t.buildings
        end
      end
    end
  end

  def test_joining_an_existing_world_stands_on_the_nearest_walkable_tile
    World.ensure_start(*TORONTO)
    again = World.ensure_start(TORONTO[0] + 0.004, TORONTO[1])
    refute_nil again
    refute_includes %w[Sea Lake Mountain], again.class.name
  end

  def test_a_new_players_character_never_starts_in_water_or_on_a_mountain
    10.times do |n|
      lng = -100.0 + n * 3.1
      user = User.new(email: "p#{n}@example.com", password: 'a good passphrase')
      user.location = World.ensure_start(lng, 40.0 + n)
      capture_io { user.save }
      assert user.saved?
      user.characters.each { |c| refute_includes %w[Sea Lake Mountain], c.location.class.name }
    end
  end

  # ---- IP lookups -------------------------------------------------------------------------
  def test_geoip_ignores_private_addresses
    with_geoip do
      GeoIP.provider = ->(_ip) { flunk 'should not look up a private address' }
      %w[127.0.0.1 10.1.2.3 192.168.0.9 172.20.0.1 ::1 not-an-ip].each { |ip| assert_nil GeoIP.locate(ip), ip }
    end
  end

  def test_geoip_returns_the_providers_answer_and_remembers_it
    with_geoip do
      calls = 0
      GeoIP.provider = ->(_ip) { calls += 1; TORONTO }
      2.times { assert_equal TORONTO, GeoIP.locate('8.8.8.8') }
      assert_equal 1, calls
    end
  end

  def test_geoip_can_be_switched_off
    with_env('GEOIP' => 'false') do
      GeoIP.provider = ->(_ip) { TORONTO }
      assert_nil GeoIP.locate('8.8.8.8')
    end
  end

  def test_the_default_lookup_reads_latitude_and_longitude_and_survives_errors
    with_geoip do
      with_env('GEOIP_URL' => 'http://127.0.0.1:1/%{ip}') do
        assert_nil GeoIP.lookup('8.8.8.8'), 'a lookup that fails gives nil, not an error'
      end
    end
  end

  # ---- the HTTP side ------------------------------------------------------------------------
  def test_locate_uses_the_browsers_position_and_starts_loading_places
    with_live do
      fetcher = live
      get '/locate', lng: TORONTO[0], lat: TORONTO[1]
      body = JSON.parse(last_response.body)
      assert_equal [-79.383, 43.653], body['coordinates']
      assert_equal 'browser', body['source']
      assert_equal 'ready', body['region']
      assert_equal 1, fetcher.calls.size
    end
  end

  def test_locate_falls_back_to_the_ip_address
    with_geoip do
      with_live do
        live
        GeoIP.provider = ->(_ip) { LONDON }
        get '/locate', {}, 'REMOTE_ADDR' => '81.2.69.142'
        body = JSON.parse(last_response.body)
        assert_equal [-0.128, 51.507], body['coordinates']
        assert_equal 'ip', body['source']
      end
    end
  end

  def test_locate_says_nothing_when_it_cannot_tell
    get '/locate'
    assert_equal 200, last_response.status
    assert_nil JSON.parse(last_response.body)['coordinates']
  end

  def test_locate_ignores_nonsense_coordinates
    get '/locate', lng: '500', lat: 'abc'
    assert_nil JSON.parse(last_response.body)['coordinates']
  end

  def test_signup_without_a_position_uses_the_ip_address
    with_geoip do
      GeoIP.provider = ->(_ip) { LONDON }
      capture_io do
        header 'Content-Type', 'application/json'
        post '/user/signup', { email: 'uk@example.com', password: 'a good passphrase' }.to_json, 'REMOTE_ADDR' => '81.2.69.142'
      end
      assert_equal 201, last_response.status
      user = User.first(email: 'uk@example.com')
      assert_in_delta LONDON[0], user.location.coordinates[0], 0.002
      assert_in_delta LONDON[1], user.location.coordinates[1], 0.002
    end
  end

  def test_signup_with_a_position_starts_there_and_loads_its_places
    with_live do
      fetcher = live
      capture_io do
        header 'Content-Type', 'application/json'
        post '/user/signup', { email: 'to@example.com', password: 'a good passphrase', coordinates: TORONTO }.to_json
      end
      assert_equal 201, last_response.status
      user = User.first(email: 'to@example.com')
      assert_in_delta TORONTO[0], user.location.coordinates[0], 0.002
      assert_equal 1, fetcher.calls.size
    end
  end

  def test_login_reports_how_the_places_are_loading
    with_live do
      live(FakeFetcher.new, inline: false)
      user = make_user('walker@example.com', 'a good passphrase')
      user.update(location: World.ensure_start(*TORONTO))
      authorize 'walker@example.com', 'a good passphrase'
      capture_io { get '/user/login' }
      assert_includes %w[loading ready], JSON.parse(last_response.body)['region']
      Overture::Regions.wait_idle
      get '/user/region'
      assert_equal 'ready', JSON.parse(last_response.body)['region']
    end
  end

  def test_region_requires_a_login
    get '/user/region'
    assert_equal 401, last_response.status
  end

  def test_places_arriving_replace_invented_buildings_on_the_next_look
    World.ensure_start(*TORONTO)
    invented = Place.count
    assert_operator invented, :>, 0
    with_live do
      live(FakeFetcher.new(places: 60, around: TORONTO))
      Overture::Regions.request(*TORONTO)
    end
    World.ensure_area(*TORONTO, 12)
    assert_operator Place.count, :>, 5
    assert Place.all.all? { |p| p.source == 'overture' }, 'invented buildings are replaced by real ones'
  end
end
