if settings.development?
  require "sinatra/reloader"
  require 'pry'
  def game_models;[Sector, Location, Place, Event, User, Character, Journey, Family, Faction, Objective]; end
  def armageddon
    omniscient
    game_models.each do |i|    
      j= i.count
      i.all.delete
      puts "#{i} was #{j}, now #{i.count} "
    end
    omnicient
    seed
  end
  def omniscient
    game_models.each do |i|
      puts "#{i} has #{i.count} entries"
    end
    nil
  end
  def seed
    User.create(email:"markpoon@me.com", password:"password", coordinates:[-79.7044534523, 43.605254354])
  end
end  

def random(x=2, y=nil)
  y == nil ? (rand(1..x)) : (rand(x..y))
end

class Array
  def to_d(d=3)
    self.map{|i|BigDecimal(i,6).floor d}
  end
  def to_f
    self.map(&:to_f)
  end
end

class Symbol
  def humanize
    self.to_s.underscore.humanize.downcase
  end
end

class Class
  def humanize
    self.to_s.underscore.humanize.downcase
  end
end

module Naming
  private
  def random_person_name(position)
    File.foreach("./lib/#{position.to_s}.txt").each_with_index.reduce(nil) { |picked,pair| rand < 1.0/(1+pair[1]) ? pair[0] : picked }.chomp.split(' ').map(&:capitalize).join(' ')
  end
end

module Entity
  def self.included(reciever)
    reciever.class_eval do
      belongs_to :location, dependent: :nullify
    end
  end
  def move(coordinates)
    unless self.location.coordinates == coordinates
      puts "\n#{self} was originally at #{self.location.coordinates}"
      self.location = Location.find_by(coordinates: coordinates)
      puts "but has moved to #{self.location.coordinates}\n"
    else
      puts "You are already at coordinates #{coordinates}."
    end
  end
  def coordinates=(coordinates)
    location_check = Location.where(coordinates: coordinates.to_d(3).to_f)
    WorldFactory.fabricate(coordinates.to_d(2).to_f) unless location_check.exists?
    self.location = location_check.first
  end
  def coordinates
    self.location.coordinates
  end
end

module Coordinates
  def self.included(reciever)
    reciever.class_eval do
      field :c, as: :coordinates, type: Array
      validates_uniqueness_of :c, message: "%{value} has already been taken"
      validates_presence_of :c
    end
  end
  def coordinates=(coordinates)
    self.c = coordinates.to_d(check_decimal(self.class)).to_f
  end
  def check_decimal(klass)
    case klass
    when *[Location, Place, Plain, Hill, Forest, ForestHill, Mountain, Lake, Sea] then return 3
    when Sector then return 2
    end
  end
end

module Targetting  
  # feed it a location or sector and it will spit back out a random coordinate
  def coordinates_in_sector(sector)
    return unless sector.class == Sector
    coordinates_array = []
    coordinates = sector.coordinates.to_d
    (coordinates[0]..(coordinates[0] + BigDecimal(0.009,3))).step(BigDecimal(0.001, 3)) do |i|
      (coordinates[1]..(coordinates[1] + BigDecimal(0.009,3))).step(BigDecimal(0.001, 3)) do |j|
        c = [i,j].map(&:to_f)
        coordinates_array << c
      end
    end
    coordinates_array
  end
  def locations_on_circle(location, r=1, r2=r+1, n=nil)
    _all = (locations_in_circle location, r2) - (locations_in_circle location, r)
  end
  def locations_in_circle(location, r=1)
    c = location.coordinates
    r = (BigDecimal r * 0.001, 3)
    return Location.within_circle(coordinates: [c, r.to_f])
  end
  def coordinates_on_box(location, r=1, r2=r+1, n=nil)
    all = (coordinates_in_box location, r2) - (coordinates_in_box location, r)
    sample_or_all all, n
  end
  def coordinates_in_box(location, r=1, n=nil)
    all =[]
    coordinates = nil
    decimal = nil
    location.class == Array ? (coordinates = location) : (coordinates = location.coordinates.to_d)
    if location.class == Location then decimal = 3 else decimal = 2; end
    (-r..r).each do |i|
      (-r..r).each do |j|
        all << [coordinates.map{|k|BigDecimal k, k.to_s.gsub(/[-.]/, '').size}, [i,j].map{|l|BigDecimal l * (0.1 ** decimal), decimal}].transpose.map(&:sum).map(&:to_f)
      end
    end
    all.delete coordinates
    return sample_or_all all, n
  end
  def sight
    self.locations_in_circle(self.location, self.vision).without(:sector_id, :faction_id).entries
  end
  private
  def sample_or_all(c, n=nil)
    c = c.sample(n) unless n == nil
    return c
  end
end

module Resources
  def self.included(reciever)
    reciever.class_eval do
      field :rw, as: :wood, type: Integer, default: ->{random 25}
      field :ro, as: :ore, type: Integer, default: ->{random 25}
      field :rf, as: :food, type: Integer, default: ->{random 25}
      field :ra, as: :water, type: Integer, default: ->{random 25}
    end
  end
  def eat(amount)
    self.inc(:food, -amount)
    self.inc(:hunger, amount)
  end
  def drink
    self.inc(:water, -amount)
    self.inc(:thirst, amount)
  end
  def build(craftsman)
  end
  def upgrade(craftsman)
  end
  def craft(craftsman)
  end
end
  
module Prestige
  def self.included(reciever)
    reciever.class_eval do
      field :rr, as: :reputation, type: Integer, default: ->{random 42}
    end
  end
  def influence(entity, amount)
    entity.inc(:influence, -amount)
    amount = -amount unless self.owner == entity
    self.inc(:influence, amount)
  end
  def reinforce(entity, amount)
    entity.inc(:soldiers, -amount)
    amount = -amount/2 unless self.owner == entity
    self.inc(:soldiers, amount)
  end
end

module CreatesEvents
  def self.included(reciever)
    reciever.extend EventMethods
  end
  module EventMethods
    def event=(seed);@event_seed = seed;end 
    def select_one(things)
      if things.class == String 
        things.constantize
      elsif things.class == Array 
        things.sample.constantize
      else
        nil
      end
    end
    def event_location; self.select_one @event_location_type; end
    def event; self.select_one @event_seed; end
  end
  def create_event(location=nil)
    Generate.event(self.class.event, location||self.class.event_location||self.location)
  end
end

module Challenge
  def self.included(reciever)
    reciever.class_eval do
      field :r, as: :reward, type: Array, default: []
      field :rd, as: :rewarded, type: Boolean, default: nil
      field :n, as: :npc, type: Array, default: []
    end
  end
  def add_npc(n=1, type=nil)
    return unless self.npc.empty?
    self.npc = case type
    when :magical
      [ :archermagesupport, :healer, :mageoffensive, :magesupport].sample(n)
    when :combat
      [:knight, :fighteroffensive, :fighterdefensive, :exoticfighter].sample(n)
    when :group
      [:fighteroffensive, :fighterdefensive, :thiefranged, :thiefcombat, :healer, :mageoffensive, :magesupport].sample(n)
    else
      [:knight, :fighteroffensive, :fighterdefensive, :exoticfighter, :thiefranged, :thiefcombat, :archer, :archermagesupport, :healer, :mageoffensive, :magesupport].sample(n)
    end
  end
  def add_reward(n = 1)
  	random(n).times{self.reward << Item.subclasses.sample.to_s.intern} 
  end
  def reward_players
    return nil if rewarded?
    self.reward.each do |item|
      binding.pry
      self.characters.each(&:items) << Generate.item(item.to_s.capitalize.constanize)
    end
  end
  private
end

module Ambition
  def self.included(reciever)
    reciever.class_eval do
      embeds_many :objectives, as: :ambitions, store_as: :a
    end
  end
  def to_s
    objectives.each(&:to_s)
  end
end