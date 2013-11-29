class Location
  include Mongoid::Document
  include Coordinates
  index({c: "2d"}, {min: -180, max: 180, unique: true, background: true})
  belongs_to :sector
  belongs_to :faction
  has_many :places
  has_many :users
  has_many :characters
  has_many :events

  def terrain
    self.class.intern unless self.class == Location
  end
  PUBLIC_JSON = {:except => [:faction_id, :sector_id, :_id], :methods => :_type, :include => {:places => Place::PUBLIC_JSON}}
  def as_json(options = PUBLIC_JSON)
    super(options).reject{|k, v| v.nil?||if v.class == Array then v.empty?; end}
  end
end

class Land < Location
  field :r, as: :resource, type: Integer, default: ->{random 9999, 99999}
  
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