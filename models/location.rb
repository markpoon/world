class Location
  include GameModel
  include Coordinates
  belongs_to :sector, required: false
  belongs_to :faction, required: false
  has n, :places
  has n, :users
  has n, :characters
  has n, :events

  def terrain
    self.class.name.to_sym unless self.class == Location
  end

  # Tiles within `radius` degrees of `center` ([lng, lat]), as a collection.
  def self.within(center, radius)
    box = all(:cx.gte => center[0] - radius, :cx.lte => center[0] + radius,
              :cy.gte => center[1] - radius, :cy.lte => center[1] + radius)
    ids = box.select { |tile| Math.hypot(tile.cx - center[0], tile.cy - center[1]) <= radius }.map(&:id)
    all(id: ids)
  end

  # set by World.preload_places so a whole map is serialized without per-tile queries
  attr_writer :preloaded_places

  # Buildings are read back through their own class (Farm, Inn, ...): see
  # World.preload_places for why.
  def buildings
    @preloaded_places || places.map { |place| place.class.get(place.id) }
  end

  # What the browser gets for a tile: id, terrain type (_type), coordinates (c),
  # the tile's resource (land only) and its buildings.
  def as_json(*)
    names = [:id, :_type]
    names << :resource if respond_to?(:resource)
    json = serialize(*names, c: :coordinates)
    list = buildings
    json['places'] = list.map(&:as_json) unless list.empty?
    json
  end
end

class Land < Location
  property :resource, Integer, required: false, default: proc { |_r, _p| random 9999, 99999 }

  def give_resource_to(entity, resource=nil)
    modifier = 1
    self.inc(:resource, -modifier)
    entity.inc(resource||:food, modifier)
  end
  def forage(user)
    give_resource_to user
  end
end

module Huntable
  def hunt(user)
    give_resource_to user
  end
end

module Choppable
  def chop(user)
    give_resource_to user, :wood
  end
end

module Minable
  def dig(user)
    give_resource_to user, :ore
  end
end

class Flats < Land
  @movement = 1
end

class Plain < Flats
  include Huntable
end

class Forest < Flats
  @movement = 2
  include Huntable
  include Choppable
end

class Heights < Land
  @movement = 2
end

class Hill < Heights
  include Minable
end

class ForestHill < Heights
  include Huntable
  include Choppable
  include Minable
end

class Mountain < Heights
  include Minable
  @movement = 3
end

class Water < Location
  def fish(user)
    give_resource_to user
  end
end

class Lake < Water
  def refill(user)
    give_resource_to user, :water
  end
end

class Sea < Water
end
