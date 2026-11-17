# A real-world business or landmark from Overture Maps (https://overturemaps.org),
# stored so the game never has to call an outside service while running.
# World.ensure_area turns the best POI on each tile into a building (see lib/overture.rb).
class PointOfInterest
  include DataMapper::Resource
  storage_names[:default] = 'points_of_interest'

  property :id,          Serial
  property :overture_id, String,  length: 64, required: true, unique_index: true
  property :name,        String,  length: 255
  property :category,    String,  length: 120   # Overture basic_category, e.g. "restaurant"
  property :section,     String,  length: 120   # top of Overture's taxonomy, e.g. "food_and_drink"
  property :building,    String,  length: 40    # the game building it becomes, e.g. "Inn"
  property :confidence,  Float
  property :lng,         Float
  property :lat,         Float
  property :ix,          Integer, index: :tile  # which 0.001-degree tile it is on
  property :iy,          Integer, index: :tile
end

# A rectangle of the world for which a POI file has been loaded. Inside it the
# map shows only real places (no invented buildings); outside it the procedural
# generator still decides.
class PoiRegion
  include DataMapper::Resource
  storage_names[:default] = 'poi_regions'

  property :id,      Serial
  property :name,    String,  length: 80, required: true, unique_index: true
  property :release, String,  length: 40
  property :west,    Float
  property :south,   Float
  property :east,    Float
  property :north,   Float
  property :places,  Integer
  # a thinly mapped area (countryside, sea): the generator still invents buildings between real ones
  property :sparse,  Boolean, default: false
  property :loaded_at, DateTime

  # Is this tile (grid position) inside the rectangle?
  def covers?(ix, iy)
    lng = ix / World::SCALE.to_f
    lat = iy / World::SCALE.to_f
    lng >= west && lng <= east && lat >= south && lat <= north
  end
end
