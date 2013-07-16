require "net/http"
require "uri"
require "bigdecimal"
require "set"

class App < Sinatra::Base
  set :public_folder, 'public'
  set :root, File.dirname(__FILE__)
  set :views, File.dirname(__FILE__) + "/views"
  enable :inline_templates
  
  Mongoid.load! "config/mongoid.yml"
  
  before "/user/*" do
    content_type 'application/json'
  end
  
  get "/?" do
    haml :index
  end
  put '/user/new' do
    user = User.where(email: @params[:email]).exists?
  end
  get '/user/login' do
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    if @auth.provided? and @auth.basic? and @auth.credentials
      email, password = @auth.credentials
      user = User.authenticate(email, password)
      if user
        status 200
        session[:user] = user.id
        u = user.sight
        return u.to_json
      else
        status 401
        return
      end
    else
      status 400
      return
    end
  end
  put '/user/logout' do
    logout!
    @user = nil
    redirect '/'
  end
  get '/user/sight' do
    user = User.find(session[:user])
    user.sight.to_json
  end
  get '/menus' do
    @options = params["path"].intern
    haml :menu, {:layout => false}
  end
  #
  get "/js/script.js" do
    content_type "text/javascript", :charset => 'utf-8'
    coffee :script
  end
  get "/js/isometric2.js" do
    content_type "text/javascript", :charset => 'utf-8'
    coffee :isometric2
  end
  get "/js/components.js" do
    content_type "text/javascript", :charset => 'utf-8'
    coffee :components
  end
  not_found{haml :'404'}
  error{@error = request.env['sinatra_error']; haml :'500'}
end

helpers do
  def authorized?; session[:user] ? (return true) : (status 403); end
  def authorize!; redirect '/login' unless authorized?; end  
  def logout!; session[:user] = false; end
end

#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#~#
def game_models;[Sector, Location, Place, Event, User, Character, Journey, Family, Faction, Objective]; end
def armageddon
  game_models.each do |i|    
    j= i.count
    i.all.delete
    puts "#{i} was #{j}, now #{i.count} "
  end
  nil
end
def omnisceient
  game_models.each do |i|
    puts "#{i} has #{i.count} entries"
  end
  nil
end
def seed
  User.create(email:"markpoon@me.com", password:"password", coordinates:[-79.7044534523, 43.605254354])
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

module Behaviors
  def self.included(reciever)
    reciever.class_eval do
      field :bi, as: :indifference, type: Integer, default: ->{random(-15, 15)} # :curiosity, likely to open or play with things vs. not wanting to interact at all.
      field :bm, as: :materialism, type: Integer, default: ->{random(-15, 15)} # :idealism, actions that will be for physical things, gold, items, property  
      field :bg, as: :greed, type: Integer, default: ->{random(-15, 15)} # :naivity, actions that will benefit themselves vs. ones that will benefit the most people.
      field :bc, as: :caution, type: Integer, default: ->{random(-15, 15)} # :spontanaity, How likely a character will choose safe vs. unsafe actions.
      field :bs, as: :stubbornness, type: Integer, default: ->{random(-15, 15)} # :indecisive, stick to previous actions despite negative progress, likelihood to change actions
      field :ba, as: :arrogance, type: Integer, default: ->{random(-15, 15)} # :passive, attempts to take :rep vs. give more :rep to others
    end
  end
  def reaction(stat, pass = 1)
    if self[stat] >= pass
      true
    else
      false
    end  
  end
  def statup=(stat)
    #self.send(up, += 1)
    stat = inverse_alignment_of(stat).map(&:sample)
    self.up[0] += random 1,2
    self.up[1] -= random 1,2
  end
  private
  def stat; [:strength, :stamina, :dexterity, :intellegence, :intuition, :resolve, :persuasion]; end
  def stat_inverse_alignment(stat)
    inverse = case stat
      when :strength then [[:arrogance, :stamina, :arrogance, :stubbornness], [:intuition, :caution, :intellegence, :nil]]
      when :stamina then [[:resolve, :stubbornness],[:caution, nil]]
      when :dexterity then [[:intellegence, :caution, :indifference],[:strength, :stamina]]
      when :intellegence then [[:greed, :arrogance],[:strength, :resolve, :intuition]]
      when :intuition then [[:persuasion, :resolve],[:caution, :stubbornness, :intellegence]]
      when :resolve then [[:stubbornness, :caution, :arrogance, :intuition],[:intellegence, :persuasion, nil ]]
      when :persuasion then [[:arrogance, :intellegence, :intuition],[:caution, :indifference]]
      else []
    end
    inverse
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

class Grid
  include Targetting
  attr_reader :vision
  def initialize(user)
    unless user.class == User
      @user = user
      @characters = user.characters
      @vision = []
      [user, characters].flatten.collect do |entity|
        @vision << view_around(entity)
      end
    else
      puts "#{user} is not an user accessing the grid."
    end
  end
  def view_around(entity)
    locations_in_circle(entity.location, entity.vision).only(:coordinates, :places).entries
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

module Inventory
  def self.included(reciever)
    reciever.class_eval do
      field :rg, as: :gold, type: Integer, default: ->{random 42}
      embeds_many :items
    end
  end
  def buys(item, seller)
    if item.price < self.gold
      self.gold -= item.price
      self.gets seller.item.pop
      seller.gold += item.price
      [self, seller].each(&:save!)
    else 
      puts "#{self.class}#{self.id} does not have enough moneys to buy item"
      return nil
    end
  end
  def sells(item, customer)
    customer.buys item, self
  end
  def drop(item)
    self.items[item].pop
  end
  def gets(items=nil)
    items = [] << items
    items.compact
    if self.carry < self.items.length + items.length
      for item in items
        self.items << item
      end
    else
      puts "too many items"
      return false
    end
  end
  private
  def carry
    (strength/4).round
  end
end

class Overpass
  def self.fabricate(sectors, types=["amenity", "shop"])
    places = []
    types.each do |t|
      places << Overpass.query(Overpass.box_coordinates(sectors), t)
    end
    places = places.flatten.compact
    places.collect! do |place|
      place = Overpass.retag place
      place = Overpass.mongoize place
    end
  end
  def self.box_coordinates(sectors)
    coordinates = sectors.map(&:coordinates).transpose
    [coordinates.first.min,coordinates.last.min,coordinates.first.max,coordinates.last.max].join(",")
  end
  def self.query(box, type)
    uri = URI.parse(URI.encode("http://www.overpass-api.de/api/xapi?node[#{type}=*][bbox=#{box}]"))
    http = Net::HTTP.new(uri.host, uri.port)
    response = http.request(Net::HTTP::Get.new(uri.request_uri))
    response = Hash.from_xml(response.body)
    response["osm"]["node"]
  end
  def self.retag(place)
    tags = place["tag"]
    if tags.class == Array
      tags.each{|i| place[i["k"]] = i["v"]}
    elsif tags.class == Hash
      place[tags["k"]] = tags["v"]
    end
    place[:overpass_id] = place["id"]
    place
  end
  def self.mongoize(place)
    place[:coordinates] = [place["lon"], place["lat"]].to_d(3).to_f
    ["tag", "id", "lat", "lon"].each{|i|place.delete i}
    place
  end
end

class WorldFactory
  extend Targetting
  def self.fabricate(coordinates)
    unprocessed, processed = SectorFactory.fabricate(coordinates)
    unprocessed.each(&:save!)
    RealmFactory.fabricate unprocessed
  end
end

class SectorFactory
  extend Targetting
  def self.fabricate(coordinates, type=nil)
    unprocessed, processed = coordinates_in_box(coordinates.to_d(2)).map{|coordinate| SectorFactory.fill_locations(coordinate)}.transpose.each(&:compact)
    if unprocessed.count > 0
      overpass = Overpass.fabricate(unprocessed).shuffle
      # overpass.each{|i| overpass.delete(i) if unprocessed.detect{|j|j.coordinates == i[:overpass_id].to_d(2).to_f}}
      locations = SectorFactory.link_location_with_places overpass, unprocessed
      unprocessed.each do |sector|
        sector.locations << sector.temporary_locations
        sector.remove_attribute :temporary_locations
      end
      locations.uniq.each(&:reload)
    end
    [unprocessed, processed]
  end
  def self.fill_locations(coordinates)
    sector = Sector.where(coordinates: coordinates)
    if sector.exists?
      sector = sector.first
      [nil, sector]
    else
      sector = sector.new(temporary_locations: [])
      type = [:rollinglands, :highlands, :lowlands] if type == nil
      type = type.sample if type.class == Array
      sector.temporary_locations = SectorFactory.create_sector_locations(sector, type)
      sector.set_name
      [sector, nil]
    end
  end
  def self.link_location_with_places(overpass, sectors)
    locations =[]
    overpass.each do |overpass_place|
      coordinates = overpass_place[:coordinates]
      sector = sectors.detect{|i| i.coordinates == coordinates.to_d(2).to_f}
      location = sector.temporary_locations.detect{|l|l.c == coordinates}
      index = sector.temporary_locations.index(location)
      overpass_place.delete :coordinates
      count = sector.temporary_locations.map(&:places).flatten.count
      place = Generate.place overpass_place, SectorFactory.place_types(count)
      unless location.class == Plain
        location = SectorFactory.bulldoze(location) 
        sector.temporary_locations[index] = location
        locations << location
      end
      location.places << place
    end
    locations
  end
  def self.place_types(count)
    case count
    when 0..4
      [Farm, Farm, Pasture]
    when 5
      Hall
    when 6..8
      [House, Pasture, Stockpile]
    when 9..15
      [Refinery, House]
    else
      [Stockpile, Refinery, Market]
    end
  end
  def self.bulldoze(location, terrain=[Plain, Hill, ForestHill, Forest].sample)
    location.becomes terrain
  end
  def self.create_sector_locations(sector, terrain)
    Generate.location coordinates_in_sector(sector), SectorFactory.terrain_types(terrain)
  end
  def self.terrain_types(type)
    case type
    when :rollinglands
      [Hill, Flats, ForestHill, Hill, Heights, Hill, ForestHill, Lake]
    when :lowlands
      [Flats, Heights, Flats, Flats, Flats, Lake, Flats]
    when :highlands
      [Heights, Flats, Heights, Heights, Heights, Lake, Heights]
    end
  end
end

class RealmFactory
  extend Targetting
  def self.fabricate(sectors)
    sectors.each do |sector|
      places = sector.locations.select{|location| location.places?}.map(&:places).flatten
      if places.count > 0
        properties = places.select{|place| [Mine, Mill, Pasture, Blacksmith, Market].include? place.class}
        places.select{|place| [Farm, Shack, House, Inn].include? place.class}.each{|place| properties = RealmFactory.populate place, properties}
        places.select{|place| place.class == Hall}.each{|place|RealmFactory.organize place, sector}
      end
    end
    RealmFactory.random_events sectors
  end
  def self.populate(place, properties)
    characters = []
    family = place.family = Generate.family({places: [place]})
    father = Character.new(gender: :male, location: place.location, residence: place, properties: [place])
    mother = Character.new(gender: :female, location: place.location, residence: place)
    father.spouse = mother
    mother.spouse = father
    family.characters << [mother, father]
    children = nil
    case place
    when Shack
      children = random 1
    when Inn
      children = random 2
    when Farm
      children = random 2, 5
    when House
      children = random 0, 3
      father.properties << properties.shuffle.pop
    end
    children.times{characters << Character.new(location: place.location, residence: place)}
    [mother, father].each{|char| char.progeny << characters } if characters.count > 0
    family.characters << characters
    RealmFactory.random_objectives family
    family.save!
    properties
  end
  def self.organize(place, sector)
    faction = Generate.faction({locations: [place.location], sectors: [sector]})
    r = ((random 2, 3).to_f/1000)
    binding.pry if place == nil
    potentialLocations = Location.within_circle(coordinates: [place.location.coordinates, r]).entries
    faction.locations << potentialLocations.sample(potentialLocations.count/2).reject{|l|l.faction?}
    faction.families = faction.locations.map(&:places).flatten.compact.map(&:family).flatten.compact.uniq
    if faction.families.empty?
      family = sector.locations.map(&:places).flatten.compact.map(&:family).flatten.compact.sample(random 2)
      family.each{|i|faction.families << i unless i.faction?}
      faction.locations << faction.families.map(&:places).flatten.compact.map(&:location).flatten.compact.uniq
    end
    faction.subjects << faction.locations.map(&:characters).flatten.compact
    RealmFactory.random_objectives faction
    faction.save!
  end
  def self.random_events(sectors)
    sectors.collect{|sector|sector.places}.flatten.each do |place|
      place.create_event
    end
  end
  def self.random_objectives(entity)
    random(3).times{Generate.objective(entity, entity.locations.sample)}
  end
end

class Generate
  extend Targetting
  def self.item(klass=Item, n=1)
    if klass.class == Fixnum
      n = klass
      klass = Item
    end
    n.times.collect do
      Generate.decide_type(klass).new
    end
  end
  def self.location(coordinates, klass=Location)
    coordinates.collect do |coordinate|
      Generate.decide_type(klass).new(coordinates: coordinate)
    end
  end
  def self.place(data, klass=Place)
    Generate.decide_type(klass).new(data)
  end
  def self.event(klass=nil, origin=nil, target=nil)
    if klass == nil    
      if origin.places?
        klass = Urban
      else
        klass = Wild
      end
    end
    Generate.decide_type(klass).new(location: origin, target: target)
  end
  def self.task(event=nil, klass=Task)
    return if event.nil?
    if klass.class == Array
      t = []
      klass.each do |task|
        t << Generate.decide_type(klass).new
      end
    else
      t = Generate.decide_type(klass).new
    end
    event.tasks << t
  end
  def self.family(data)
    Generate.decide_type(Family).new(data)
  end
  def self.faction(data)
    Generate.decide_type(Source).new(data)
  end
  def self.objective(klass, location)
    l = locations_in_circle(location).first
    within_borders = klass.locations.include? l
    has_place = Set.new(klass.places).subset?(Set.new(l.places))
    options = []
    if within_borders and has_place
      options = [Construction, Upgrade, Urban]
    elsif within_borders
      options = [Construction, Wild]
    elsif has_place
      options = case klass.class
      when Family.superclass
        [Raid, Travellers, TradeWith]
      when Faction.superclass
        [Raid, Travellers, Conquer, TradeWith]
      end
    else
      options = [Wild]
    end
    e = Generate.event(options.sample, l)
    e.save!
    klass.objectives << Objective.new(event: e)
  end
  def self.chapter(journey, klass)
    binding.pry
    journey.chapters << Generate.decide_type(klass).new 
  end
  def self.decide_type(klass)
    klass = klass.sample if klass.class == Array
    while !klass.subclasses.empty?
      klass = klass.subclasses.sample
    end
    klass
  end
end

class Sector
  include Mongoid::Document
  include Coordinates
  has_many :locations
  has_and_belongs_to_many :factions
  validates_length_of :locations, minimum: 100, maximum: 100
  validates_presence_of :locations
  field :p, as: :prefix, type: Symbol
  field :s, as: :suffix, type: Symbol
  def name
    [prefix, suffix].map(&:to_s).join(" ")
  end
  def set_name
    self.prefix = [["Aber","Ast","Auch","Ach","Bal","Brad","Car","Caer","Din","Dinas","Gill","Kin","King","Kirk","Lan","Lhan","Llan","Lang","Lin","Pit","Pol","Pont","Stan","Tre","Win","Whel"], ["shire","mire","more","wick","dale","ay","ey","y","bourne","burn","brough","burgh","bury","by","carden","cardine","don","den","field","forth","ghyll","ham","holme","kirk","mere","port","stead","wick"]].map(&:sample).join.intern
    distribution = location_distribution
    self.suffix = case distribution.max_by{|k, v| v}[0]
    when :Plain then [:Plains, :Flats, :Fields, :Grasslands, :Meadows, :Moorland, :Prairie, :Steppe].sample
    when :Forest then [:Forest, :Grove, :Timberlands, :Wildwoods, :Brake, :Chase, :Coppice, :Copse, :Cover, :Bosk, :Orchard].sample
    when *[:Hill, :ForestHill] then [:Foothill, :Hillside, :Mound, :Knoll, :Butte, :Bluff, :Ridge, :Highlands].sample
    when :Mountain then [:Peak, :Mountains, :Mount, :Summit, :Alp, :Sierra, :Cordillera, :Massif].sample
    when :Lake then [:Lake, :Creek, :Pool, :Sluice, :Spring, :Tarn, :Basin].sample
    when :Sea then [:Sea, :Ocean].sample
    end
  end
  def location_distribution
    distribution, location_types = {}, []
    locations.only(:_type).each{|i| location_types << i._type.intern}
    [:Plain, :Forest, :ForestHill, :Hill, :Mountain, :Lake, :Sea].each do |i|
      distribution[i] = location_types.count i
    end
    distribution
  end
  def places
    locations.map(&:places).flatten.compact
  end
  def events
    locations.map(&:events).flatten.compact
  end
  after_create do
    puts "Generated #{self.name}, #{self.coordinates}"
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

class User
  include Mongoid::Document
  include Entity
  include Targetting
  PUBLIC_JSON = {:only => [:_id, :n, :faction_id], :methods => :vision}

  has_many :characters, dependent: :nullify
  belongs_to :faction, dependent: :nullify
  
  field :e, as: :email, type: String
  field :s, as: :salt, type: String
  field :h, as: :hashed_password, type: String
  
  validates_presence_of :location, :email, :salt, :hashed_password
  
  field :n, as: :energy, type: Integer, default: ->{random 15, 30}
  field :v, as: :vision, type: Integer
  
  field :l, as: :slots, type: Integer
    
  def vision; self.v||5;end
  def slots;self.l||1;end
  def nearby_location(distance = 5)
    potential_locations = (locations_in_circle self.location, distance).all.sample(15)
    candidate_location = potential_locations.pop
    while potential_locations.length > 0 and ![Sea, Lake, Mountain].include? candidate_location.class do
      candidate_location = potential_locations.pop
    end
    candidate_location
  end
  after_create do
    puts "#{self.email} has joined the game, they're at #{self.location.coordinates}"
    # Pony.mail(to: self.email, subject: "Welcome to the Cosmic Dream #{self.email}", body: "Don't forget that your password is \"#{@password}\"")
    self.characters.create!(location: nearby_location)
  end
  def password=(pass)
    @password = pass
    self.salt = User.random_string(15) unless self.salt
    self.hashed_password = User.encrypt(@password, self.salt)
  end
  def self.authenticate(email, pass)
    u = User.find_by(email: email)
    return nil if u.nil?
    return u if User.encrypt(pass, u.salt) == u.hashed_password
    nil
  end
  def sight
    response = {}
    sectors = (self.characters.collect(&:location).flatten.compact.collect(&:sector).flatten.compact << self.location.sector).uniq
    locations = sectors.collect(&:locations).flatten.compact
    return locations.as_json
  end
  def as_json(options = PUBLIC_JSON)
    super(options).reject{|k, v| v.nil?||if v.class == Array then v.empty?; end}
  end
    
  protected
  def self.encrypt(pass, salt)
    Digest::SHA2.hexdigest(pass + salt)
  end
  def self.random_string(len)
    chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
    str = ""
    1.upto(len) { |i| str << chars[Random.new.rand(chars.size-1)] }
    return str
  end
end

class Stats
  include Mongoid::Document
  field :sw, as: :wound, type: Integer
  field :sc, as: :scratch, type: Integer
  field :si, as: :injury, type: Integer
  field :se, as: :energy, type: Integer
  field :ss, as: :status, type: Hash
  def scratch_max
    (self.resolve + self.dexterity * 1.618 - (self.injury||0)).round
  end  
  def scratch
    scratch_max - scratch
  end
  def wound_max
    (self.stamina * 3 + self.resolve - (self.injury||0 * 1.618)).round
  end
  def energy_max
    self.intellegence + self.intuition * 2 + self.resolve
  end
  def energy
    e||energy_max
  end
  field :st, as: :thirst, type: Integer, default: ->{random 80,100}
  field :su, as: :hunger, type: Integer, default: ->{random 80,100}
  field :sl, as: :sleep, type: Integer, default: ->{random 80,100} 
  
  field :ss, as: :strength, type: Integer, default: ->{random 5,15}
  field :st, as: :stamina, type: Integer, default: ->{random 5,15}
  field :sd, as: :dexterity, type: Integer, default: ->{random 5,15}
  field :sp, as: :persuasion, type: Integer, default: ->{random 5,15}
  field :si, as: :intellegence, type: Integer, default: ->{random 5,15}
  field :su, as: :intuition, type: Integer, default: ->{random 5,15}
  field :sr, as: :resolve, type: Integer, default: ->{random 5,15}

  def check(stat, pass = 1, difficulty = 1)
    result = []
    difficulty.times do 
      if self[stat] + random(-10, 10) >= pass
        result << true
      else
        result << false
      end
    end
    (result.count(true) >= (result.length / 2).round) ? (true) : (false)
  end
end

module Skills
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

class Chapter
  include Mongoid::Document
  include Challenge
  embedded_in :journey
  field :e, type: Integer
  
  around_create do
    set_step
    generate_tasks
  end
  def event=
    binding.pry
    self.journeys.events
  end
  def event
    binding.pry
    self.journeys.events[e]
  end
  def tell_story
    puts "there should be a subplot focused on a single location with tasks to re-enforce that one goal."
  end
end

class Departure < Chapter
end
class Departed <Chapter
end
class Initiation < Chapter
end
class Initiated < Chapter
end
class Returning < Chapter
end
class Returned < Chapter
end

class TheCall < Departure
end
class Aid < Departure
end
class Threshold < Departed # This goes first
end
class Metamorphosis < Departed # This goes first
end
class Trial < Initiated
end
class Training < Initiation
end
class Vision < Initiation
end
class Intrigue < Initiation
end
class Temptation < Initiated
end
class Descent < Initiated
end
class Atonement < Initiated
end
class Return < Returned
end
class Boon < Returning
end
class Apotheosis < Returning
end
class Flight < Returning
end
class Mastery < Returned
end
class Choices < Returned
end
class Rescue < Returned
end

module Enchanted
  def self.included(reciever)
    reciever.class_eval do
      has_and_belongs_to_many :abilities, inverse_of: nil
    end
  end
      
  def charge_max
    l = self.durability
    if self.material == (:wood || :leather)
      l *= 2
    else
      l *= 0.7
    end
    if self.slot == (:finger || :neck || :head)
      l *= 1.5
    else
      l *= 0.7
    end
    l.round
  end
  def price
    base_price + (charge/charge_max * 4)
  end
  private
  def use_item; puts "it's magical!"; true; end
end

class Item
  include Mongoid::Document
  embedded_in :character
  
  field :m, as: :material, type: Symbol
  field :q, as: :quality, type: Integer, default: ->{random 10,24}
  field :d, as: :durability, type: Integer, default: ->{random 10,24}
  
  field :e, as: :effect, type: Symbol
  field :c, as: :charge, type: Integer
  field :n, as: :enchanted, type: Boolean
  
  after_initialize do
    self.class.send(:include, Enchanted) if enchanted
  end
  
  def material=(m)
    self.m = case 
    when m.class == Array
      m.sample
    else
      m
    end
    case material
    when :crystal
      self.quality += random(4,8)
      self.durability -= random(6,9)
      when *[:glass, :paper]
        self.quality += random(2,6)
        self.durability -= random(5,8)
    when *[:gold, :silver] then
      self.quality += random(3,5)
      self.durability -= random(3,4)
    when *[:wood, :leather] then
      self.quality -= random(3,7)
      self.durability -= random(1,2)
    when *[:iron, :steel]
      self.durability += random(5,8)
    end
    
  end

  def durability
    self.d||durability_max
  end
  
  def durability_max
    l = self.quality * 1.618 
    if self.effect
      l -= self.effect.length * 0.7
    end
    if self.material == :iron
      l *= 2
    elsif self.material == :steel
      l *= 3.14
    else
      l *= 0.7
    end
    binding.pry if l == 0
    l.round
  end
  
  def name; self.class.to_s; end
  def portrait; name + (durability / 10 + 1).to_s; end
  def price; base_price; end
  def use; use_charge if use_item; end
  PUBLIC_JSON = {:except => :e, :methods => [:_type, :durability, :durability_max, :portrait, :price]}
  def as_json(options = PUBLIC_JSON)
    super(options).reject{|k, v| v.nil?||if v.class == Array then v.empty?; end}
  end
  
  private
  def base_price
    p = (quality * 2)
    case self.material
    when :crystal
      p *= 3.14 
    when :gold 
      p *= 3  
    when:silver 
      p *= 2
    when :steel 
      p *= 1.2
    end
    p * (durability/durability_max)
  end
  def use_charge; charge > 1 ? (self.inc(:charge, -1)) : (self.delete); end
  def use_item; puts "you used an item!"; false; end
  def location
    character.location
  end 
end
class Ability
  include Mongoid::Document
  
  field :n, as: :name, type: String
  field :r, as: :range, type: Integer
  field :a, as: :area, type: Integer
  
  field :e, as: :effect, type: Symbol
  field :v, as: :value, type: Integer
  field :d, as: :duration, type: Integer
  
  field :t, as: :cost_type, type: Symbol
  field :c, as: :cost, type: Integer

  def teach(character)
    character.abilities << self
  end  

  def use(target=origin, origin)
    return unless #check for range
    if area
      targets = #targets in area
      targets.each{|t| affect t}
    else
      affect target
    end
    origin.inc(cost_type, cost)
  end
  PUBLIC_JSON = {}
  def as_json(options={})
    super(options).reject{|k, v| v.nil?||if v.class == Array then v.empty?; end}
  end
  private
  def affect(target)
    target.send(effect, value, duration)
  end
end

class Character < Stats
  include Mongoid::Timestamps::Created
  include Entity
  include Naming
  include Behaviors
  include Skills
  include Prestige
  include Inventory
  include Targetting
  
  belongs_to :user, dependent: :nullify
  
  has_many :properties, inverse_of: :owner, class_name: "Place"
  belongs_to :employed, inverse_of: :employees, class_name: "Place"
  belongs_to :residence, inverse_of: :residents, class_name: "Place"
  
  belongs_to :family
  has_and_belongs_to_many :progenitors, inverse_of: :progeny, class_name: "Character"
  has_one :spouse, inverse_of: :spouse, class_name: "Character"
  belongs_to :spouse, inverse_of: :spouse, class_name: "Character"
  has_and_belongs_to_many :progeny, inverse_of: :progenitors, class_name: "Character"
  validate :check_character_limit, :check_progenitors, on: :create
  
  has_and_belongs_to_many :abilities, inverse_of: nil
  
  def name; lastname ? ([firstname, lastname].join(' ')) : (firstname); end
  field :n, as: :firstname, type: String 
  def lastname; self.family ? (self.family.name) : (nil); end

  field :p, as: :portrait, type: String
  field :a, as: :age, type: Integer, default: ->{random 12, 26}
  field :v, as: :vision, type: Integer
  field :g, as: :female?, type: Boolean, default: ->{[nil, true].sample}
  field :x, as: :homosexual?, type: Boolean, default: ->{[nil, nil, true, nil, nil].sample}
  
  belongs_to :allegience, class_name: "Faction", inverse_of: :subjects, dependent: :nullify
  
  field :f, as: :faction_attitude, type: Symbol

  has_and_belongs_to_many :journeys, dependent: :nullify
  field :j, as: :journey_attitude, type: Symbol
  
  after_initialize do
    unless persisted?
      self.firstname = random_person_name self.gender unless self.firstname
      starting_items if items.empty?
    end
  end
  
  def gender
    self.female? ? (:female) : (:male)
  end
  def gender=(gender)
    gender == :female ? (self.g = true) : (self.g = nil)
  end
  def sexuality
    self.homosexual? ? (:homosexual) : (:heterosexual)
  end
  def sexuality=(sex)
    sex == :homosexual ? (self.x = true) : (self.x = true)
  end
  def vision
    self.v||1
  end
  PUBLIC_JSON = {:except => [:created_at, :x, :q, :n, :ability_ids, :journey_ids, :f, :location_id, :v], :methods => [:vision, :name, :gender], :include => {:items => Item::PUBLIC_JSON, :abilities=> Ability::PUBLIC_JSON}}
  def as_json(options = PUBLIC_JSON)
    s = super(options)
    s.reject{|k, v| v.nil?||if v.class == Array then v.empty?; end}
  end
  private
  
  def starting_items
    item_classes = case self.age
    when 12..16
      [Weapon, BodyArmor]
    when 17..21
      [Weapon, BodyArmor, [Accessory, Tool]]
    when 22..30
      [Weapon, BodyArmor, [Accessory, Tool, Weapon], [Accessory, Tool, HeadArmor]]
    else 
      [Weapon, BodyArmor, [Accessory, Tool, Weapon], [Accessory, Gemstone, HeadArmor], [Gemstone, Potion, Rune]]
    end
    self.items = item_classes.collect{|i| Generate.item i}.flatten
  end
  def check_character_limit
    return if user.blank?
    errors.add(:base, "This user does not have enough slots open for a new character") if self.user.characters.count >= self.user.slots
  end
  def check_progenitors
    errors.add(:base, "Why does this character have more than two parents?") if progenitors.count > 2
  end
end

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
  PUBLIC_JSON = {:except => [:faction_id, :sector_id, :_id], :methods => :_type, :include => {:places => Place::PUBLIC_JSON, :users => User::PUBLIC_JSON, :characters => Character::PUBLIC_JSON}}
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

class Journey
  include Mongoid::Document
  include Mongoid::Timestamps::Created
  include Targetting
  has_and_belongs_to_many :characters
  field :o, as: :role, type: Array, default: [:protagonist]
  
  has_and_belongs_to_many :events
  embeds_many :chapters, store_as: "e"
  
  has_and_belongs_to_many :sectors, inverse_of: nil
  has_and_belongs_to_many :objectives
  
  field :h, as: :herald, type: Symbol, default: ->{[:aDyingDelivery, :foundAMysteriousObject, :mistakenIdentity, :mysteriousCharacterAppears, :gaveAPromise, :someRandomViolence].sample}
  field :p, as: :plot, type: Symbol, default: ->{[:toMassacreInnocent, :toSubvertLeadership, :anInvasion, :toReleaseAncientEvil, :toPlotRevolt, :toStealResources].sample}
  field :f, as: :conflict, type: Symbol, default: -> {[:society, :superstition, :technology].sample}
  field :n, as: :nemesis, type: Symbol, default: ->{[:spymaster, :zealot, :leader, :slaver, :destroyer, :disguisedmonster, :wizard].sample}
  field :t, as: :twist, type: Array, default: ->{[:doubleagent, :misdirection, :trap, :wards, :seperatedFromTheGroup, :duel, :neutralPartyCaptured, :allyCaptured].sample}
  field :r, as: :progress, type: Symbol, default: :departure
  
  around_create do
    trace_journeys_path
    self.chapters = [TheCall.new(journey: self)]
  end
  
  before_save do
    check_progress
    assign_character_roles
  end
  
  def trace_journeys_path
    3.times do |i|
      c = coordinates_on_box sectors.last, 2+i, 3+i, 1
      sectors.find_or_create_by(coordinates: c)
    end
  end
  def assign_character_roles
    role << [:mentor, :sidekick, :skeptic, :logical, :foil, :underdog].sample if characters.count < role.count
  end
  def role(character)
    i = characters.find_index character
    role[i]
  end
  def check_progress
    puts "checking this Journey's Progress... Currently #{self.progress} and the chapter length is: #{self.chapters.length}"
    self.progress = case self.chapters.length
    when 0...2 
      :departure
    when 3...5 
      (self.progress == :departure and random(3) == 1) ? (:departure) : (:departed)
    when 5...7
      self.progress = :initiation
    when 8...12 
      (self.progress == :initiation and random(3) == 1) ? (:initiation) : (:initiated)
    when 13..14
      :returning
    when 15..16
      (self.progress == :returning or random(5) == 4) ? (:returning) : (:returned)
    else
      :returned
    end
    loop create_chapter until self.chapters > 4
    puts self.progress
  end
  def create_chapter
    binding.pry
    Generate.chapters self, self.progress
  end
  
  after_create do
    tell_story
  end
  
  def tell_story
    puts "Once upon a time, in #{self.characters.first.location.sector.name} #{self.characters.first.location.sector.coordinates}, our hero; #{characters.first.name} was just going about his day when #{self.herald.humanize} happened."
    puts "In an epic struggle against #{self.conflict}, our heroes faces a #{self.nemesis} planning #{self.plot.humanize}."
    chapters.each{|c| c.tell_story}
  end  
end

class Gemstone < Item
  after_initialize do
    unless self.material then self.material = :crystal end
  end
end

class Readable < Item
  after_initialize do
    unless self.material then self.material = :paper end
  end
  field :r, as: :read, type: String
end

class Tool < Item
  around_create do
    self.charge = quality
  end
end

class LockPicks < Tool
  after_initialize do
    unless self.material then self.material = [:iron, :steel] end
  end
  private
  def use_item(obj)
    obj.send(:unlock)
  end
end

class FlintAndSteel < Tool
  after_initialize do
    unless self.material then self.material = :steel end
  end
  private
  def use_item(target)
    target.send(:burn)
  end
end

class Potion < Item
  after_initialize do
    unless self.material then self.material = :glass end
  end
  include Enchanted
  field :a, as: :attribute, type: Symbol
  def use_item
  end
end

class Rune < Item
  include Enchanted
  after_initialize do
    unless self.material then self.material = [:paper, :leather] end
  end
  def use_item(target)
    self.delete if ability.use(target, charge)
  end  
end

class Key < Item
  after_initialize do
    unless self.material then self.material = [:wood, :iron, :steel] end
  end
  field :o, as: :lock, type: Moped::BSON::ObjectId
  validates_presence_of :lock
  def unlock(obj)
    obj.id == lock ? (obj.send(:unlock)) : (puts "This key does not unlock this object")
  end
end

class Equipment < Item
  field :l, as: :slot, type: Symbol
  field :u, as: :equipped, type: Boolean
  
  def equip
    for item in character.items
      item.equipped = nil if item.slot == self.slot and items.equipped == true
    end
  end
end

class Weapon < Equipment
  around_create do
    self.slot = [:hand, :hands].sample
  end
  def damage; base_damage; end
  private
  def base_damage; self.quality/6 + @damage||1; end
end

module RangedWeapon
  def range; base_range; end
  private
  def base_range; self.quality / 6 + @range||1;end
end

class Wand < Weapon
  include RangedWeapon
  @damage = 2
  @range = 4
  after_initialize do
    unless self.material then self.material = [:wood, :iron, :steel, :silver, :gold] end
  end
end

class Axe < Weapon
  @damage = 4
  after_initialize do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class Sword < Weapon
  @damage = 5
  after_initialize do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class Dagger < Weapon
  @damage = 3
  after_initialize do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class Mace < Weapon
  @damage = 4
  after_initialize do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class Bow < Weapon
  @damage = 3
  @range = 5
  include RangedWeapon
  after_initialize do
    unless self.material then self.material = :wood end
  end
end

class Sling < Weapon
  include RangedWeapon
  @damage = 2
  @range = 3
  after_initialize do
    unless self.material then self.material = :leather end
  end
end
  
class Armor < Equipment
  def defense; base_defense; end
  private
  def base_defense
    quality/2 + @defense||1 * (durability/ durability_max)
  end
end

class Shield < Armor
  after_initialize do
    unless self.material then self.material = :wood end
  end
end

class MetalShield < Armor
  @defense = 2
  after_initialize do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class BodyArmor < Armor
end

class LeatherArmor < BodyArmor
  @defense = 2
  after_initialize do
    unless self.material then self.material = :leather end
  end
end

class Chainmail < BodyArmor 
  @defense = 3
  after_initialize do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class PlateArmor < BodyArmor
  @defense = 4
  after_initialize do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class HeadArmor < Armor
  @defense = 1
  after_initialize do
    unless self.material then self.material = [:leather, :iron, :steel] end
  end
end

class Accessory < Equipment
  after_initialize do
    unless self.material then self.material = [:leather, :iron, :steel, :silver, :gold] end
  end
end

class Ring < Accessory
  after_initialize do
    unless self.material then self.material = [:silver, :gold] end
  end
end

class Necklace < Accessory
  after_initialize do
    unless self.material then self.material = [:leather, :silver, :gold] end
  end
end

module Taskable
  def self.included base 
    base.class_eval do
      field :t, as: :target, type: Moped::BSON::ObjectId
      field :c, type: String
      field :d, as: :completed, type: Boolean, default: nil
    end
    base.extend DefaultTask
  end
  module DefaultTask; attr_accessor :tasks_default; end
  def generate_tasks
    unless self.class.tasks_default == nil
      self.class.tasks_default.each do |event|
        if random(3) == 2 or self.class < Event
          Generate.task self, Object.const_get(event)
        end
      end
    end   
    self.tasks 
  end
  def to_s
    tasks.collect{|task| task.to_s }.join('. ') unless tasks?
  end
    
  def complete
    if complete? and completed
      after_complete
      completed = true
    end 
  end
  def complete?
    progress = 0 if progress.nil?
    if (!tasks? and progress >= 100) or (tasks.all?(&:complete?) and progress >= 100)
      true
    else
      false
    end
  end
  def after_complete
    reward_players
  end
  def target=(target)
    return if target.nil? or !target.respond_to?(:id)
    self.t = target.id
    self.c = target.class.to_s
  end
  def target
    return if (c or t) == nil
    c.constantize.find(t)
  end
end

class Event
  include Mongoid::Document
  include Mongoid::Timestamps::Created
  include Challenge
  include Taskable
  embeds_many :tasks, as: :assignment, store_as: :a
  belongs_to :location
  has_and_belongs_to_many :journeys
  after_initialize do
    unless persisted?
      generate_tasks
      add_reward
      add_npc
    end
  end
  before_save do
    complete if complete?
  end
  def characters
    journeys.collect(&:characters).flatten.compact.uniq
  end
  def to_s
    reply = ["At #{self.location.class}#{self.location.coordinates}, a #{self.class} event is occuring"]
    unless tasks.empty?
      reply << "it has #{self.tasks.count} tasks:"
      reply << tasks.collect(&:to_s)
    end
    reply.join(', ')
  end
end

class Wild < Event
end
class Supply < Event
  field :x, as: :count, type: Integer, default: ->{random 10}
  def after_complete
    location.inc(:resource, -count)
    target.inc(self.supply, count)
  end
end
class Logging < Supply
  @tasks_default = [['Escort', 'Procure', 'Theft', 'Espionage', 'Courier'].sample] 
  @supply = :wood
end
class Harvesting < Supply
  @tasks_default = [['Escort', 'Procure', 'Theft', 'Espionage', 'Courier'].sample]
  @supply = :food
end
class Hunting < Supply
  @tasks_default = [['Combat', 'Procure', 'Theft', 'Courier'].sample]
  @supply = :food
end
class Foraging < Supply
  @tasks_default = [['Escort', 'Espionage', 'Courier', 'Procure', 'Theft'].sample]
  @supply = :food
end
class Fishing < Supply
  @tasks_default = [['Courier', 'Procure', 'Espionage', 'Theft'].sample]
  @supply = :food
end
class Excavating < Supply
  @tasks_default = [['Courier', 'Procure', 'Espionage', 'Theft'].sample]
  @supply = :ore
end
  
class Travellers < Wild
  after_initialize do
    if target.nil?
      self.target = self.location.sector.locations.sample
    end
  end
  after_update do
    self.complete if arrived?
  end
  def arrived?;
    self.location == self.target
  end
end
class Explorers < Travellers
  @tasks_default = [['Scout', 'Combat'].sample]
end 
class Lost < Travellers
  @tasks_default = [['Escort', 'Pursue'].sample] + random(4).times.collect{['Combat', 'Courier', 'Combat'].sample}
end
class Merchants < Travellers
  @tasks_default = [['Resourcing', 'Negotiation', 'Courier', 'Combat'].sample]
end
class Bandits < Travellers
  @tasks_default = [['Negotiation', 'Combat'].sample]
end
class Settlers < Travellers
  @tasks_default = [['Resourcing', 'Diplomacy', 'Courier', 'Combat'].sample]
end
class Refugees < Travellers
  @tasks_default = [['Resourcing', 'Negotiation', 'Courier', 'Combat'].sample]
end
class Construction < Event
  field :p, as: :place, type: String, default: ->{["House", "Home", "Farm"].sample}
  @tasks_default = random(6).times.collect{['Resourcing', 'Courier'].sample}
  def complete
  end
end
class Urban < Event
end
class UrbanPlace <  Event
  after_initialize do
    if target.nil?
      self.target = self.location.places.sample
    end
  end
end
class TradeWith < UrbanPlace
  @tasks_default = random(4).times.collect{['Resourcing', 'Negotiation'].sample}
end
class Upgrade < UrbanPlace
  @tasks_default = random(6).times.collect{['Resourcing', 'Courier'].sample}
end
class Fair < Urban
  @tasks_default = random(6).times.collect{['Espionage','Resourcing', 'Courier'].sample}
end
class Banquet < Urban
  @tasks_default = random(5, 8).times.collect{['Espionage', 'Negotiation'].sample}
end
class Tournament < Urban
  @tasks_default = random(5, 8).times.collect{['Espionage', 'Negotiation', 'Combat'].sample}
end
class Council < Urban
  # An assembly of persons who meet for a common purpose especially a meeting 
  # of delegates for the purpose of formulating a written agreement on specific 
  # issues. 
  @tasks_default = random(3).times.collect{['Courier', 'Escort'].sample} << 'Treaty'  
end

class War < Event
end
class Recon < War
  @tasks_default = random(3).times.collect{['Espionage', 'Escort', 'Combat'].sample}
end
class Conquer < War
  @tasks_default = random(3,5).times.collect{['Espionage', 'Combat', 'Courier', 'Combat'].sample}
end
class Raid < War
  @tasks_default = random(4).times.collect{['Espionage', 'Combat', 'Courier', 'Combat'].sample}
end
class Assassinate < War
  @tasks_default = random(6).times.collect{['Espionage', 'Combat', 'Espionage'].sample}
end

class Task
  include Mongoid::Document
  include Taskable
  embeds_many :tasks, as: :assignment, store_as: :a
  embedded_in :assignment, polymorphic: true
  field :p, as: :progress, type: Integer
  after_initialize do
    unless persisted?
      generate_tasks
    end
  end
  def complete?
    binding.pry if self.p.class == Symbol
    self.p != nil and self.p > 100 ? (true) : (false) 
  end
  def to_s
    phrase = ["#{self.class.humanize.capitalize}"]
    case
    when self.respond_to?(:count)
      phrase << "#{self.count}"
    when self.respond_to?(:resource)
      phrase << "#{self.resource}"
    when self.respond_to?(:target)
      phrase << "to get #{self.target||'[target not found]'}"
    when self.respond_to?(:destination) 
      phrase << "to #{self.destination||'[destination not found]'}"
    end
    phrase << self.progress
    unless tasks.empty?
      phrase << "it has tasks: "
      phrase << self.tasks.collect(&:to_s)
    end
    phrase.join(', ')
  end
  def progress
    "and is #{p||0}% complete."
  end
end

class Resourcing < Task
  field :x, as: :count, type: Integer, default: ->{random 25}
  field :r, as: :resource, type: Symbol, default: ->{[:wood, :ore, :food, :water].sample}

  around_create do
    binding.pry
    self.target = assignment
  end
end
class Trade < Resourcing
  @tasks_default = ['Negotiation']
end
class Procure < Resourcing
  @tasks_default = random(3).times.collect{['Courier', 'Combat'].sample} 
end
class Theft < Resourcing
  @tasks_default = random(3).times.collect{['Courier', 'Procure'].sample} 
end
class Craft < Task
  @tasks_default = random(3).times.collect{['Courier', 'Procure'].sample} 
  before_create do
    target = Item.subclasses.sample.to_s
  end
  def after_complete
    Generate(target.constantize, count)
  end
end

class Courier < Task
  field :d, type: Moped::BSON::ObjectId
  def destination= location;self.d = location.coordinates;end
  def destination;Location.find_by(coordinates: self.d);end
  def delivered?
    return true if target.location == destination
  end
end
class Deliver < Courier
  @tasks_default = random(3).times.collect{['Combat', 'Espionage'].sample}
end
class Escort < Courier
  @tasks_default = random(3).times.collect{['Combat', 'Espionage'].sample}
end
class Retrieve < Courier
  @tasks_default = random(3).times.collect{['Combat', 'Espionage'].sample}
  # def to_s
  #   "#{self.class} #{self.target||'target not found'} and bring it to #{self.destination||'destination not found'}"
  # end
end
class Pursue < Courier
  @tasks_default = random(3).times.collect{['Combat', 'Espionage'].sample}
  # def to_s
  #   "#{self.class} #{self.target||'target not found'} before it arrives at #{self.destination||'destination not found'}"
  # end
end

class Diplomacy < Task
  field :e, as: :entities, type: Moped::BSON::ObjectId
end
class Negotiation < Diplomacy
  # def to_s
  #   "#{self.class} between #{self.entities.join(', ')||'entities not found'}"
  # end
end
class Embargo < Diplomacy
  # an order of a government prohibiting the departure of commercial ships and 
  # other vehicles from its ports. It is a legal prohibition on commerce.
  field :pr, as: :prohibits, type: Symbol, default: ->{[:food, :ore, :wood, :items].sample}
  # def to_s
  #   "#{self.entities} seek to implement a #{self.prohibits} #{self.class} against #{self.target}"
  # end
end
class Treaty < Diplomacy
  # An agreement or arrangement made by negotiation; a contract in writing 
  # between two or more political authorities such as sovereign states, 
  # formally signed by authorized representatives, and usually approved by 
  # the legislature of the state.
  # def to_s
  #   "#{self.class} between #{self.entities} to #{self.target}"
  # end
end
class Borders < Treaty
  field :o, as: :open?, type: Boolean, default: true
  # def to_s
  #   "#{open? ? ("Open") : ("Closed")} #{self.class} between #{self.entities} to #{self.target}"
  # end
end
class Tariff < Treaty
  field :g, as: :goods, type: Symbol, default: ->{[:food, :ore, :wood, :items].sample}
  field :t, as: :tax, type: Integer, default: ->{random(1,5)}
  # def to_s
  #   "A #{self.tax} gold #{self.class} between #{self.entities} on all #{self.goods}"
  # end
end
class NonAggression < Treaty
end
class Alliance < Treaty
end
class Capitulate < Treaty
end
class Independence < Treaty
end

class Espionage < Task
end
class Scout < Espionage
end
class Liberate < Espionage
end
class Ambush < Espionage
end
class Sabatoge < Espionage
end
class Escape < Espionage
end
class Pursued < Espionage
end
class Kidnap < Espionage
end

class Combat < Task
end
class CombatAggressive < Combat
end
class Destroy < CombatAggressive

end
class Capture < CombatAggressive
end
class CombatCount < Combat
  field :x, as: :count, type: Integer, default: ->{random 5, 10}
end
class Rally < CombatCount
end
class CaptureTheFlag < CombatCount
end
class Survive < CombatCount
end
class Hostages < CombatCount
end
class Protect < Combat
end
class HoldPosition < Combat
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

class Family
  include Mongoid::Document
  include Mongoid::Timestamps::Created
  include Naming
  include Ambition
  has_many :characters
  has_many :places
  belongs_to :faction
  
  field :n, as: :name, type: String
  field :s, as: :speciality, type: Symbol
  
  after_initialize do
    unless persisted?
      self.name = random_person_name :family
      specialize if speciality.nil?
    end
  end
  def specialize
    puts "base classes cannot specialize"
  end
  def locations
    self.places.collect{|i|i.location}.uniq
  end
  def fullname
    "The #{name} #{self.class}"
  end
  
end
class Guild < Family
  def specialize
    self.speciality = [:food, :wood, :ore, :gold, :item, :construction].sample
  end
end
class Band < Family
  def specialize
    self.speciality = [:combat, :trade, :gold, :item].sample
  end
end
class Clan < Family
  def specialize
    self.speciality = [:food, :wood, :ore, :gold].sample
  end
end

class Faction
  include Mongoid::Document
  include Mongoid::Timestamps::Created
  include Naming
  include Ambition
  has_and_belongs_to_many :sectors
  has_many :families
  has_many :locations  
  has_many :subjects, class_name: "Character", inverse_of: :allegience # ids of users that can make changes
  belongs_to :master, inverse_of: :vassals, class_name: "Faction"
  field :p, as: :prefix, type: Symbol
  def name;"The #{families.empty? ? (self.prefix) : (self.families.first.name)} #{self.class.to_s}";end
  def places; locations.collect(&:places).flatten.compact; end
  def halls; places.select{|i|i._type == "Hall"}; end
  def upkeep;1 * 0.2 ** subject.count + 1 ** 1.7 ** locations.count;end
  def issueQuest(character)
    if character.journey.last.complete == true ? (character.journey.create!(faction: self)) : (puts 'this character has an active journey'); end
  end
  after_create do
    puts "  #{self.name} controls #{self.locations.count} land with #{self.objectives.count} objectives"
    puts "    #{self.families.count} houses, #{self.families.collect(&:name).join(", ")} are vying for control of this #{self.class}" if self.families.count > 1
  end
end
class Source < Faction
end
class Authoritarian < Source
end
class Autocracy < Authoritarian
end
class Dictatorship < Authoritarian
end
class Oligarchy < Source
end
class Plutocracy < Oligarchy
end
class Aristocracy < Oligarchy
end
class Theocracy < Source
end
class Monarchy < Source
end
class Democracy < Source
end
class Republic < Source
end

class Structured < Faction
  has_many :vassals, inverse_of: :master, class_name: "Faction"
end
class Empire < Structured
  # ruled either by a monarch (emperor, empress) or an oligarchy
end
class Confederation < Structured
  # a permanent union of political units for common action in relation to other units.
  # Usually created by treaty but often later adopting a common constitution, 
  # confederations tend to be established for dealing with critical issues (such as 
  # defense, foreign affairs, or a common currency), with the central government being
  # required to provide support for all members.
end
class Federation < Structured
   # a union of partially self-governing states or regions united by a central government.
   # In a federation, the self-governing status of the component states, as well as the
   # division of power between them and the central government, are typically constitutionally
   # entrenched and may not be altered by a unilateral decision of the states.
end
class Hegemony < Structured
  # an indirect form of government of imperial dominance in which the hegemon (leader state)
  # rules geopolitically subordinate states by the implied means of power, the threat of force,
  # rather than by direct military force.
end

class Objective
  include Mongoid::Document
  include Targetting
  embedded_in :ambitions, polymorphic: true
  field :a, type: Boolean, default: true
  field :e, type: Moped::BSON::ObjectId
  field :j, type: Moped::BSON::ObjectId
  
  def event=(event); self.e = event.id; end
  def event; Event.find(e) unless e.nil?; end
  def journey=(journey); self.j = journey.id; end
  def journey; Journey.find(j) unless j.nil?; end
  def action; a.nil?; end
  def describe
    event.describe
  end
end
# Binding.pry
__END__

@@index
#cr-stage

@@layout
!!! 5
%html
  %head
    %title Cosmic - Geolocation game written in coffeescript, lovely.io, crafty.js, backend in ruby, sinatra, mongodb
    %meta{name: "viewport", content: "width=device-width,user-scalable=0,initial-scale=1.0,minimum-scale=0.5,maximum-scale=1.0"}
    %link{href: "css/style.css", rel: "stylesheet"}
  %body
    = yield
  %footer
  %script{src: "http://cdn.lovely.io/core.js", type: "text/javascript"}
  %script{src: "/js/underscore-min.js", type: "text/javascript"}  
  %script{src: "/js/crafty.js", type: "text/javascript"}
  %script{src: "/js/isometric2.js", type: "text/javascript"}
  %script{src: "/js/components.js", type: "text/javascript"}
  %script{src: "/js/script.js", type: "text/javascript"}

@@menu
#menu
  = render 'haml', @options

@@login
%input{:type => "text", :id =>"loginEmail", :name => "email", :placeholder => "Your@Email.com"}
%input{:type => "text", :id =>"loginPassword", :name => "password", :placeholder => "Pass Phrase"}
%button{:id =>"loginButton"} Login to Cosmic
  
@@404
.warning
  %h1 404
  %hr 
  Apologies, there were no results found for your query.
  %hr
  
@@500
.warning
  %h1 500
  %hr
  %p @error.message
  %hr
