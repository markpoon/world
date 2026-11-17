# Real places from Overture Maps become buildings in the game.
#
#   tools/fetch_overture.py   (developer, once)  downloads places for a bounding box
#                             into data/overture/<name>.csv.gz (+ a .json with the box)
#   Overture.load_bundled!    (every boot)       loads any new file into points_of_interest
#   World.ensure_area         (as players walk)  puts the best place on each tile
#
# Overture Places are CDLA-Permissive-2.0 licensed: https://docs.overturemaps.org/
require 'csv'
require 'json'
require 'zlib'
require 'open3'
require 'tmpdir'
require 'fileutils'

module Overture
  DATA_DIR = File.expand_path('../data/overture', __dir__)

  # Which building a category becomes. The first rule that matches the Overture
  # category (e.g. "coffee_shop") or taxonomy path wins; the order matters.
  # Rules match whole words (split on underscores or spaces), so "park" does not match "parking".
  def self.words(*list); /(?:\A|[_\s])(?:#{list.join('|')})(?:[_\s]|\z)/; end
  RULES = [
    ['Mine',      words('mining', 'quarry')],
    ['Farm',      words('farm', 'agricultural', 'agriculture', 'nursery', 'orchard', 'winery', 'vineyard', 'garden_center')],
    ['Pasture',   words('park', 'golf_course', 'zoo', 'animal', 'pet', 'stable', 'campground', 'playground', 'stadium', 'swimming_pool')],
    ['Castle',    words('historic_site', 'museum', 'monument', 'landmark', 'castle', 'art_gallery', 'airport')],
    ['Barrack',   words('police', 'fire_station', 'military', 'gym', 'fitness', 'sport_or', 'sport_league', 'martial')],
    ['Inn',       words('restaurant', 'eatery', 'cafe', 'coffee_shop', 'bar', 'pub', 'hotel', 'motel', 'lodging',
                        'brewery', 'bakery', 'food_service', 'smoothie_juice_bar', 'beverage_venue', 'nightclub')],
    ['Market',    /store|shop|mall|market|grocery|pharmacy|gas_station|convenience|wholesale|retail|atm/],
    ['Blacksmith', /automotive|vehicle|auto_dealer|manufactur|industrial|machine|construction|repair|tire|welding|plumb|electrician|hvac/],
    ['Mill',      /warehouse|storage|supplier|distributor|logistics|freight|shipping|transport|taxi/],
    ['House',     /real_estate|home_service|senior_living|housing|apartment|residential/],
    ['Hall',      /church|worship|school|college|university|government|civic|community|hospital|clinic|health|dental|bank|financial|attorney|law|legal|office|professional|insurance|accountant|education/]
  ].freeze

  # Used when no rule matches: the top of the Overture taxonomy.
  SECTION_BUILDINGS = {
    'food_and_drink' => 'Inn', 'lodging' => 'Inn', 'shopping' => 'Market',
    'community_and_government' => 'Hall', 'education' => 'Hall', 'health_care' => 'Hall',
    'services_and_business' => 'Hall', 'cultural_and_historic' => 'Castle',
    'sports_and_recreation' => 'Pasture', 'travel_and_transportation' => 'Mill'
  }.freeze
  FALLBACK = 'Shack'.freeze

  def self.building_for(category, section = nil, taxonomy = nil)
    text = "#{category} #{taxonomy}".downcase
    RULES.each { |building, rule| return building if text =~ rule }
    SECTION_BUILDINGS.fetch(section.to_s, FALLBACK)
  end

  # --- loading ---------------------------------------------------------------
  BATCH = 100
  COLUMNS = %w[overture_id name category section building confidence lng lat ix iy].freeze

  # Load every data/overture/*.csv.gz that has not been loaded yet. Safe on every boot.
  def self.load_bundled!(dir = DATA_DIR)
    Dir[File.join(dir, '*.csv.gz')].sort.map { |file| load_file(file) }.compact
  end

  # Load one file (and record the rectangle it covers). Returns the PoiRegion, or
  # nil if that file's release was already loaded. The .json beside it says what
  # it is: name, release, the box, and optionally "sparse_below" (a region with
  # fewer places than that is thinly mapped: the generator fills the gaps).
  def self.load_file(file)
    meta = JSON.parse(File.read(file.sub(/\.csv\.gz\z/, '.json')))
    existing = PoiRegion.first(name: meta['name'])
    return nil if existing && existing.release == meta['release']
    if existing # a newer release replaces the old one, inside its own box
      PointOfInterest.all(:lng.gte => existing.west, :lng.lte => existing.east,
                          :lat.gte => existing.south, :lat.lte => existing.north).destroy!
    end
    adapter = DataMapper.repository.adapter
    quoted  = ->(name) { adapter.send(:quote_name, name) }
    count = 0
    PoiRegion.transaction do
      rows = []
      flush = lambda do
        next if rows.empty?
        marks = rows.map { "(#{(['?'] * COLUMNS.size).join(',')})" }.join(',')
        adapter.execute("INSERT INTO #{quoted.('points_of_interest')} (#{COLUMNS.map { |c| quoted.(c) }.join(',')}) " \
                        "VALUES #{marks} ON CONFLICT (#{quoted.('overture_id')}) DO NOTHING", *rows.flatten)
        count += rows.size
        rows.clear
      end
      Zlib::GzipReader.open(file) do |gz|
        CSV.new(gz.read.force_encoding('UTF-8').scrub, headers: true).each do |row|
          lng = row['lng'].to_f
          lat = row['lat'].to_f
          ix, iy = World.grid(lng, lat)
          rows << [row['id'], row['name'].to_s[0, 255], row['category'], row['group'],
                   building_for(row['category'], row['group'], row['taxonomy']),
                   row['confidence'].to_f, lng, lat, ix, iy]
          flush.call if rows.size >= BATCH
        end
      end
      flush.call
      region = existing || PoiRegion.new(name: meta['name'])
      region.attributes = { release: meta['release'], west: meta['west'], south: meta['south'],
                            east: meta['east'], north: meta['north'], places: count, loaded_at: DateTime.now,
                            sparse: meta['sparse_below'] ? count < meta['sparse_below'].to_i : false }
      region.save
    end
    PoiRegion.first(name: meta['name'])
  end

  # --- reading ---------------------------------------------------------------
  def self.covered?(ix, iy, regions = PoiRegion.all.to_a)
    regions.any? { |region| region.covers?(ix, iy) }
  end

  # The most trusted place on each tile in a rectangle of the grid:
  # { [ix, iy] => PointOfInterest }
  def self.best_by_tile(ix_range, iy_range)
    found = PointOfInterest.all(:ix.gte => ix_range.min, :ix.lte => ix_range.max,
                                :iy.gte => iy_range.min, :iy.lte => iy_range.max)
    found.to_a.group_by { |poi| [poi.ix, poi.iy] }.transform_values do |list|
      list.max_by { |poi| [poi.confidence.to_f, -poi.id] }
    end
  end
end

# Getting places for wherever a player turns up, while the app is running.
#
# Overture publishes its data as Parquet files on S3. DuckDB (a Python
# package, driven by tools/fetch_overture.py) reads just the part inside a box.
module Overture
  module Fetcher
    class Error < StandardError; end

    DEFAULT_RELEASE = '2026-10-21.0'.freeze
    TIMEOUT = 300 # seconds

    SCRIPT = File.expand_path('../tools/fetch_overture.py', __dir__)

    class << self
      def python; ENV.fetch('PYTHON', 'python3'); end

      def release
        value = ENV['OVERTURE_RELEASE'].to_s
        value =~ /\A\d{4}-\d\d-\d\d\.\d+\z/ ? value : DEFAULT_RELEASE
      end

      # Can we fetch? Needs Python with the duckdb package.
      def available?
        return @available unless @available.nil?
        @available = begin
          Open3.capture2e(python, '-c', 'import duckdb')[1].success?
        rescue SystemCallError
          false
        end
      end

      def reset!; @available = nil; end

      # Download the places in a box. Returns the path of a csv.gz in a new
      # temporary folder (the caller deletes the folder).
      def call(name, west, south, east, north, release = self.release)
        dir = Dir.mktmpdir('overture')
        args = [python, SCRIPT, '--out', dir, name.to_s, *[west, south, east, north].map { |v| Float(v).to_s }, release.to_s]
        Open3.popen3(*args) do |stdin, _stdout, stderr, waiter|
          stdin.close
          unless waiter.join(TIMEOUT)
            Process.kill('KILL', waiter.pid)
            raise Error, "the download took longer than #{TIMEOUT}s"
          end
          raise Error, "the download failed: #{stderr.read.to_s.strip[-300..-1]}" unless waiter.value.success?
        end
        out = File.join(dir, "#{name}.csv.gz")
        raise Error, 'the download wrote no file' unless File.exist?(out)
        out
      rescue StandardError
        FileUtils.rm_rf(dir) if dir
        raise
      end
    end
  end

  # The world is cut into fixed squares ("cells", 0.1 degrees, roughly 8 x 11 km).
  # The first time anyone needs a cell it is fetched in the background and
  # stored; from then on it is just database rows. Until it arrives the generator
  # invents buildings, and World.ensure_area swaps them for real ones afterwards.
  module Regions
    CELL = 0.1
    EDGE = 0.01 # also fetch the next cell when this close to its edge (degrees)
    MAX_QUEUE = 4
    RETRY_AFTER = 600
    PER_REQUESTER_PER_HOUR = 6
    SPARSE_BELOW = 50
    LOCK = Mutex.new
    @jobs = {}      # cell name => { state: :queued | :running | :failed, at: Time, error: String }
    @queue = Queue.new
    @starts = []    # [Time, requester] of every fetch started, for the limits

    class << self
      # Tests: a callable like Fetcher.call, and run jobs right away instead of in a thread.
      attr_accessor :fetcher, :inline

      def daily_limit; Integer(ENV.fetch('OVERTURE_MAX_CELLS_PER_DAY', '40')); end

      def enabled?
        AppEnv.overture_live? && (!fetcher.nil? || Fetcher.available?)
      end

      def cell(lng, lat); [(lng / CELL).floor, (lat / CELL).floor]; end
      def name_for(i, j); "cell_#{i}_#{j}"; end

      def box(i, j)
        [i, j, i + 1, j + 1].map { |v| (v * CELL).round(6) }
      end

      def covered?(lng, lat)
        ix, iy = World.grid(lng, lat)
        PoiRegion.all.any? { |region| region.covers?(ix, iy) }
      end

      # :ready (places are loaded), :loading, :failed, :idle (nothing asked for yet)
      # or :unavailable (switched off, or DuckDB is not installed)
      def status(lng, lat)
        return :ready if covered?(lng, lat)
        job = LOCK.synchronize { @jobs[name_for(*cell(lng, lat))] }
        return :loading if job && %i[queued running].include?(job[:state])
        return :failed if job && job[:state] == :failed && Time.now - job[:at] < RETRY_AFTER
        enabled? ? :idle : :unavailable
      end

      # Make sure the cell around this point (and the next one, near an edge) is
      # loaded or on its way. Returns the same symbols as status, plus :limited
      # when a limit was reached.
      def request(lng, lat, requester = nil)
        result = request_cell(lng, lat, requester)
        i, j = cell(lng, lat)
        edges = []
        edges << lng - EDGE if lng - i * CELL < EDGE
        edges << lng + EDGE if (i + 1) * CELL - lng < EDGE
        near_lat = []
        near_lat << lat - EDGE if lat - j * CELL < EDGE
        near_lat << lat + EDGE if (j + 1) * CELL - lat < EDGE
        (edges.map { |x| [x, lat] } + near_lat.map { |y| [lng, y] }).each { |x, y| request_cell(x, y, requester) }
        result
      end

      def request_cell(lng, lat, requester)
        return :ready if covered?(lng, lat)
        return :unavailable unless enabled?
        i, j = cell(lng, lat)
        name = name_for(i, j)
        job = nil
        LOCK.synchronize do
          current = @jobs[name]
          return :loading if current && %i[queued running].include?(current[:state])
          return :failed if current && current[:state] == :failed && Time.now - current[:at] < RETRY_AFTER
          now = Time.now
          @starts.reject! { |at, _| now - at > 86_400 }
          return :limited if @starts.size >= daily_limit
          return :limited if requester && @starts.count { |at, who| who == requester && now - at < 3600 } >= PER_REQUESTER_PER_HOUR
          return :limited if @queue.size >= MAX_QUEUE
          @starts << [now, requester]
          job = @jobs[name] = { state: :queued, at: now, name: name, cell: [i, j] }
        end
        inline ? run(job) : (enqueue(job))
        status(lng, lat)
      end

      def enqueue(job)
        @queue << job
        LOCK.synchronize do
          @worker = Thread.new { loop { run(@queue.pop) } } unless @worker&.alive?
        end
      end

      def run(job)
        LOCK.synchronize { job[:state] = :running }
        i, j = job[:cell]
        west, south, east, north = box(i, j)
        csv = (fetcher || Fetcher).call(job[:name], west, south, east, north, Fetcher.release)
        begin
          File.write(csv.sub(/\.csv\.gz\z/, '.json'),
                     { name: job[:name], release: Fetcher.release, west: west, south: south, east: east, north: north,
                       sparse_below: SPARSE_BELOW }.to_json)
          Overture.load_file(csv)
        ensure
          FileUtils.rm_rf(File.dirname(csv))
        end
        LOCK.synchronize { @jobs.delete(job[:name]) }
        puts "Overture: loaded #{job[:name]}"
      rescue StandardError => e
        LOCK.synchronize { job.merge!(state: :failed, at: Time.now, error: e.message) }
        warn "Overture: could not load #{job[:name]}: #{e.message}"
      end

      # Tests: wait until every queued fetch has finished.
      def wait_idle(timeout = 20)
        deadline = Time.now + timeout
        sleep 0.02 while Time.now < deadline && LOCK.synchronize { @jobs.values.any? { |j| %i[queued running].include?(j[:state]) } }
      end

      def reset!
        LOCK.synchronize do
          @jobs.clear
          @starts.clear
          @queue.clear
        end
      end
    end
  end
end
