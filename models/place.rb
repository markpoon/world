class Place
  include GameModel
  include Resources
  include CreatesEvents
  property :soldiers, Integer, required: false
  belongs_to :family, required: false
  belongs_to :location, required: false
  belongs_to :owner, 'Character', required: false
  def portrait
    self.class.to_s
  end
  def name; self.class.to_s; end
  # Starts an event of this building's kind, on a nearby tile of the right terrain.
  def create_event(target_location=nil)
    self.reload if self.location == nil
    wanted = self.class.event_location
    if target_location.nil? and !wanted.nil?
      nearby = Location.within(location.coordinates, 0.005).select { |tile| tile.is_a?(wanted) }
      target_location = nearby.sample
    else
      target_location = self.location
    end
    location.events << super(target_location)
    location.save
    location.events.last
  end

  # What the browser gets for a building: its id, kind (_type), name and resources.
  def as_json(*)
    names = [:id, :_type, :name, :family_id, :owner_id, :wood, :ore, :food, :water]
    names << :gold if respond_to?(:gold)
    serialize(*names)
  end
end


module Employment
  def self.included(reciever)
    reciever.class_eval do
      has n, :employees, 'Character', child_key: [:employed_id]
    end
  end
end
module Occupancy
  def self.included(reciever)
    reciever.class_eval do
      has n, :residents, 'Character', child_key: [:residence_id]
    end
  end
end
module Commerce
  @event_location_type, @event_seed= ['Plain', 'Hill'], 'TradeWith'
  def trade
    create_event
  end
end
class Market < Place
  include Inventory
  include Prestige
  include Employment
  include Commerce
end
class Hall < Place
  include Prestige
  include Employment
  include Commerce
  @event_location_type, @event_seed= ['Hill', 'Mountain'], 'TradeWith'
  def faction
    self.owner.family||nil
  end
end

 # Hunting, Foraging, Fishing
class Stockpile < Place
  include Employment
  def gather(entity, supply)
    amount = -self.employees.count
    if self.location.inc(supply, amount)
      entity.inc(supply, amount)
    else
      puts "resource exhausted at #{self.location.coordinates}"
    end
  end
  private
end
module Husbandry
  def self.included base
    base.class_eval do
      @event_location_type, @event_seed = ['Plain', 'Hill'], 'Harvesting'
    end
  end
  def harvest(character)
    create_event
  end
end
class Pasture < Stockpile
  include Husbandry
end
class Mine < Stockpile
  @event_location_type, @event_seed= ['Hill', 'ForestHill', 'Mountain'], 'Excavating'
  def dig(character)
    create_event
  end
end

class Refinery < Place
  include Inventory
  include Employment
end
class Farm < Refinery
  include Husbandry
  include Occupancy
end
class Blacksmith < Refinery
end
class Mill < Refinery
  @event_location_type, @event_seed = ['Forest', 'ForestHill'], 'Harvesting'
  def chop(location, characters)
    create_event location, characters
  end
end

class Martial < Place
  include Prestige
end
class Barrack < Martial
  @event_location_type, @event_seed = ['Plain', 'Hill', 'ForestHill'], 'Scout'
  def assemble
    create_event
  end
end
class Castle < Martial
end

class Lodging < Place
  include Inventory
  include Occupancy
  def stay(character)
    character.rest if character.journey.last.characters.includes? self.owner
  end
end
class Shack < Lodging
end
class Inn < Lodging
  include Employment
  include Prestige
  def stay(character, cost)
    return if (character or cost) == nil
    if character.gold - cost > 0
      character.inc(:gold, -cost)
      character.rest
      inc(:gold, cost)
    else
      puts "not enough gold"
    end
  end
end
class House < Lodging
  include Employment
  include Prestige
end