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