# Procedural world generator. Replaces the original WorldFactory/Overpass import,
# which needed the OpenStreetMap API and Mongoid-only features.
#
# The map is a grid of 0.001-degree tiles. Terrain and buildings are a pure
# function of a tile's grid position, so every caller gets the same world, and
# tiles are only written to the database the first time somebody can see them.
require 'zlib'
require 'set'
require_relative 'overture'

module World
  SCALE      = 1000 # tiles per degree (the rest of the app uses 3 decimals)
  # Where new players start (grid position of -79.708, 43.607). The 3x3 around
  # it is always open plains with no buildings, so nobody spawns in water.
  SPAWN      = [-79_708, 43_607].freeze
  MAX_RADIUS = 12   # never generate more than 25x25 tiles per call
  LOCK       = Mutex.new # one generator at a time inside this process

  # --- deterministic noise -------------------------------------------------
  def self.lattice(x, y, salt)
    Zlib.crc32("#{salt}:#{x}:#{y}") / 4_294_967_295.0
  end

  # smooth value noise: random values on a coarse lattice, smoothly interpolated
  def self.noise(x, y, cell, salt)
    gx = x.to_f / cell
    gy = y.to_f / cell
    x0 = gx.floor
    y0 = gy.floor
    fx = gx - x0
    fy = gy - y0
    sx = fx * fx * (3 - 2 * fx)
    sy = fy * fy * (3 - 2 * fy)
    a = lattice(x0, y0, salt);     b = lattice(x0 + 1, y0, salt)
    c = lattice(x0, y0 + 1, salt); d = lattice(x0 + 1, y0 + 1, salt)
    top    = a + (b - a) * sx
    bottom = c + (d - c) * sx
    top + (bottom - top) * sy
  end

  def self.elevation(ix, iy); 0.65 * noise(ix, iy, 14, 'elevation') + 0.35 * noise(ix, iy, 5, 'elevation2'); end
  def self.moisture(ix, iy);  0.70 * noise(ix, iy, 10, 'moisture')  + 0.30 * noise(ix, iy, 4, 'moisture2');  end

  def self.spawn_clearing?(ix, iy)
    (ix - SPAWN[0]).abs <= 1 && (iy - SPAWN[1]).abs <= 1
  end

  # Near the spawn point the land is eased toward gentle terrain (no deep water,
  # no mountains that would block a new player in); further out it is untouched.
  FRIENDLY_INNER  = 3.0  # tiles from spawn where the effect is strongest
  FRIENDLY_OUTER  = 12.0 # ...and where it fades out completely
  FRIENDLY_PULL   = 0.5  # how far elevation is pulled toward 0.5 at the centre

  def self.friendly_elevation(ix, iy, e)
    d = Math.hypot(ix - SPAWN[0], iy - SPAWN[1])
    t = ((d - FRIENDLY_INNER) / (FRIENDLY_OUTER - FRIENDLY_INNER)).clamp(0.0, 1.0)
    t = t * t * (3 - 2 * t)
    pull = FRIENDLY_PULL * (1 - t)
    e * (1 - pull) + 0.5 * pull
  end

  def self.terrain_for(ix, iy)
    return Plain if spawn_clearing?(ix, iy)
    e = friendly_elevation(ix, iy, elevation(ix, iy))
    m = moisture(ix, iy)
    return Sea  if e < 0.30
    return Lake if e < 0.35 && m > 0.50
    if e > 0.71
      Mountain
    elsif e > 0.62
      m > 0.52 ? ForestHill : Hill
    elsif m > 0.56
      Forest
    else
      Plain
    end
  end

  PLACES = {
    'Plain'      => %w[House House Farm Shack Inn Market Pasture],
    'Forest'     => %w[Shack Mill],
    'Hill'       => %w[Mine Pasture Barrack Shack],
    'ForestHill' => %w[Shack Mill],
    'Mountain'   => %w[Mine Mine Castle]
  }.freeze
  PLACE_CHANCE = 0.07

  def self.place_for(terrain, ix, iy)
    choices = PLACES[terrain.name]
    return nil if spawn_clearing?(ix, iy)
    return nil unless choices && lattice(ix, iy, 'place') < PLACE_CHANCE
    Object.const_get(choices[(lattice(ix, iy, 'kind') * choices.size).floor])
  end

  # --- tiles ---------------------------------------------------------------
  def self.grid(lng, lat); [(lng.to_f * SCALE).round, (lat.to_f * SCALE).round]; end

  def self.tile_at(lng, lat)
    ix, iy = grid(lng, lat)
    Location.first(cx: ix / SCALE.to_f, cy: iy / SCALE.to_f)
  end

  # Load the buildings for a batch of tiles in a few queries and attach them to
  # each tile (tile.preloaded_places), ready for Location#as_json.
  #
  # Buildings are read back through their own class (Farm, Inn, ...) because
  # DataMapper's single-table inheritance cannot lazy-load a subclass-only field
  # such as a Farm's gold through a query on the base Place class.
  def self.preload_places(locations)
    return locations if locations.empty?
    rows = Place.all(location_id: locations.map(&:id)).to_a
    hydrated = rows.group_by(&:class).flat_map { |klass, group| klass.all(id: group.map(&:id)).to_a }
    by_tile = hydrated.group_by(&:location_id)
    locations.each { |tile| tile.preloaded_places = by_tile[tile.id] || [] }
    locations
  end

  BLOCKING = %w[Sea Lake Mountain].freeze

  # Real places (Overture Maps, see lib/overture.rb) take priority over invented
  # ones. Where a region of real data has been loaded, tiles with no real place
  # stay empty rather than getting a made-up building.
  def self.build_place(tile, terrain, ix, iy, poi, covered)
    if poi
      Object.const_get(poi.building).create(location: tile, title: poi.name, category: poi.category,
                                            source: 'overture', source_id: poi.overture_id)
    elsif !covered
      klass = place_for(terrain, ix, iy)
      klass.create(location: tile) if klass
    end
  end

  # Bring a tile that already exists in line with what the generator says it
  # should hold now (tiles from older versions, or a newly loaded data file).
  def self.sync_place(tile, ix, iy, poi, covered, current)
    if poi
      return if current.size == 1 && current.first.source_id == poi.overture_id
      return if BLOCKING.include?(tile.class.name) # a real place never sits in the sea
      current.each(&:destroy)
      build_place(tile, tile.class, ix, iy, poi, covered)
    elsif covered
      current.each(&:destroy)
    elsif current.empty?
      build_place(tile, tile.class, ix, iy, nil, false)
    end
  end

  # Make sure every tile within `radius` of (lng, lat) exists, and that tiles
  # created by earlier versions of the generator have the buildings the
  # generator says they should. Safe to call often. Returns tiles created.
  def self.ensure_area(lng, lat, radius = 5)
    radius = [[radius.to_i, 0].max, MAX_RADIUS].min
    cx, cy = grid(lng, lat)
    LOCK.synchronize do
      half = 0.5 / SCALE
      tiles = Location.all(
        :cx.gte => (cx - radius) / SCALE.to_f - half, :cx.lte => (cx + radius) / SCALE.to_f + half,
        :cy.gte => (cy - radius) / SCALE.to_f - half, :cy.lte => (cy + radius) / SCALE.to_f + half
      ).to_a
      existing = {}
      tiles.each { |l| existing[[(l.cx * SCALE).round, (l.cy * SCALE).round]] = l }
      places = tiles.empty? ? {} : Place.all(location_id: tiles.map(&:id)).to_a.group_by(&:location_id)
      regions = PoiRegion.all.to_a
      pois = regions.empty? ? {} : Overture.best_by_tile((cx - radius)..(cx + radius), (cy - radius)..(cy + radius))

      created = 0
      Location.transaction do
        (-radius..radius).each do |dx|
          (-radius..radius).each do |dy|
            ix = cx + dx
            iy = cy + dy
            poi = spawn_clearing?(ix, iy) ? nil : pois[[ix, iy]]
            covered = !poi.nil? || regions.any? { |region| region.covers?(ix, iy) }
            if (tile = existing[[ix, iy]])
              sync_place(tile, ix, iy, poi, covered, places[tile.id] || [])
              next
            end
            terrain = terrain_for(ix, iy)
            terrain = Plain if poi && BLOCKING.include?(terrain.name) # real places sit on land
            tile = terrain.create(cx: ix / SCALE.to_f, cy: iy / SCALE.to_f)
            build_place(tile, terrain, ix, iy, poi, covered)
            created += 1
          end
        end
      end
      created
    end
  end

  # When a player steps onto a tile, make sure the squares next to it exist
  # (building them, with their real or invented places, if they do not), and
  # return them ready to send to the browser. `reach` is how many squares out
  # to go: 1 is the eight neighbours.
  ADJACENT_MAX = 3
  def self.populate_adjacent(lng, lat, reach = 1)
    reach = [[reach.to_i, 1].max, ADJACENT_MAX].min
    created = ensure_area(lng, lat, reach)
    cx, cy = grid(lng, lat)
    half = 0.5 / SCALE
    tiles = Location.all(
      :cx.gte => (cx - reach) / SCALE.to_f - half, :cx.lte => (cx + reach) / SCALE.to_f + half,
      :cy.gte => (cy - reach) / SCALE.to_f - half, :cy.lte => (cy + reach) / SCALE.to_f + half
    ).to_a
    preload_places(tiles)
    { created: created, tiles: tiles }
  end
end
