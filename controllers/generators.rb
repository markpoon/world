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