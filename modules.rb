if AppEnv.development?
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
    omniscient
    seed
  end
  def omniscient
    game_models.each do |i|
      puts "#{i} has #{i.count} entries"
    end
    nil
  end
  def seed
    Seed.demo_user!
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
      belongs_to :location, required: false
    end
  end
  def move(coordinates)
    unless self.location.coordinates == coordinates
      puts "\n#{self} was originally at #{self.location.coordinates}"
      self.location = Location.at(coordinates)
      puts "but has moved to #{self.location.coordinates}\n"
    else
      puts "You are already at coordinates #{coordinates}."
    end
  end
  # Put the entity on the tile at these [lng, lat] coordinates (building the map there if needed).
  def coordinates=(coordinates)
    lng, lat = coordinates.map(&:to_f)
    World.ensure_area(lng, lat, 0)
    self.location = World.tile_at(lng, lat)
  end
  def coordinates
    self.location.coordinates
  end
end

module Coordinates
  def self.included(reciever)
    reciever.class_eval do
      property :cx, Float, required: false, index: true
      property :cy, Float, required: false, index: true
    end
  end
  def coordinates
    [cx, cy]
  end
  def coordinates=(coordinates)
    self.cx, self.cy = coordinates.to_d(check_decimal(self.class)).to_f
  end
  def check_decimal(klass)
    klass <= Sector ? 2 : 3
  end
end

module Targetting  
  # Helpers for finding tiles around a location.
  def locations_on_circle(location, r=1, r2=r+1, n=nil)
    _all = (locations_in_circle location, r2) - (locations_in_circle location, r)
  end
  def locations_in_circle(location, r=1)
    c = location.coordinates
    r = (BigDecimal r * 0.001, 3)
    Location.within(c, r.to_f)
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
    locations_in_circle(location, vision).to_a
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
      property :wood, Integer, required: false, default: proc { |_r, _p| random 25 }
      property :ore, Integer, required: false, default: proc { |_r, _p| random 25 }
      property :food, Integer, required: false, default: proc { |_r, _p| random 25 }
      property :water, Integer, required: false, default: proc { |_r, _p| random 25 }
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
      property :reputation, Integer, required: false, default: proc { |_r, _p| random 42 }
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
      list :reward, default: []
      property :rewarded, Boolean, required: false
      list :npc, default: []
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
  	random(n).times{self.reward << Item.descendant_classes.sample.to_s.intern} 
  end
  def reward_players
    return nil if rewarded?
    self.reward.each do |item|
      characters.each { |character| character.items.concat(Generate.item(item.to_s.capitalize.constantize)) }
    end
  end
  private
end

module Ambition
  def self.included(reciever)
    reciever.class_eval do
      # Families and factions each own their objectives (Objective belongs_to both)
      has n, :objectives, 'Objective', child_key: [:"#{reciever.name.underscore}_id"]
    end
  end
  def to_s
    objectives.each(&:to_s)
  end
end