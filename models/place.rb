class Place
  include Mongoid::Document
  include Resources
  include CreatesEvents
  field :s, as: :soldiers, type: Integer
  belongs_to :family
  belongs_to :location
  validates_associated :location
  belongs_to :owner, inverse_of: :properties, class_name: "Character"
  def portrait
    self.class.to_s
  end
  def create_event(target_location=nil)
    self.reload if self.location == nil
    if target_location.nil? and !self.class.event_location.nil?
      target_location = self.class.event_location.near(coordinates: self.location.coordinates).max_distance(c: 0.005).sample
    else
      target_location = self.location
    end
    binding.pry if target_location.nil?
    location.events << super(target_location)
    location.save
    location.events.last
  end
  PUBLIC_JSON = {:only => [:_id, :_type, :name, :family_id, :owner_id, :rw, :rg, :ro, :ra, :rf]}
  def as_json(options={})
    super(options).reject{|k, v| v.nil?||if v.class == Array then v.empty?; end}
  end
end


module Employment
  def self.included(reciever)
    reciever.class_eval do
      has_many :employees, inverse_of: :employed, class_name: "Character"
    end
  end
end
module Occupancy
  def self.included(reciever)
    reciever.class_eval do
      has_many :residents, inverse_of: :residence, class_name: "Character"
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
    if self.location.inc(amount, supply)
      entity.inc(amount, supply)
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
      character.inc(-cost, :gold)
      character.rest
      self.gold.inc(cost, :gold)
    else
      puts "not enough gold"
    end
  end
end
class House < Lodging
  include Employment
  include Prestige
end