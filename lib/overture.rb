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
  # nil if that file's release was already loaded.
  def self.load_file(file)
    meta = JSON.parse(File.read(file.sub(/\.csv\.gz\z/, '.json')))
    existing = PoiRegion.first(name: meta['name'])
    return nil if existing && existing.release == meta['release']
    PointOfInterest.all.destroy if existing # a newer release replaces the old
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
                            east: meta['east'], north: meta['north'], places: count, loaded_at: DateTime.now }
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
