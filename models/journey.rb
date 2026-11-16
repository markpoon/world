class Journey
  include GameModel
  include Targetting
  has n, :characters, through: DataMapper::Resource
  list :role, default: [:protagonist]

  has n, :events, through: DataMapper::Resource
  has n, :chapters
  has n, :sectors, through: DataMapper::Resource
  has n, :objectives, through: DataMapper::Resource

  symbol :herald, default: ->{[:aDyingDelivery, :foundAMysteriousObject, :mistakenIdentity, :mysteriousCharacterAppears, :gaveAPromise, :someRandomViolence].sample}
  symbol :plot, default: ->{[:toMassacreInnocent, :toSubvertLeadership, :anInvasion, :toReleaseAncientEvil, :toPlotRevolt, :toStealResources].sample}
  symbol :conflict, default: ->{[:society, :superstition, :technology].sample}
  symbol :nemesis, default: ->{[:spymaster, :zealot, :leader, :slaver, :destroyer, :disguisedmonster, :wizard].sample}
  symbol :twist, default: ->{[:doubleagent, :misdirection, :trap, :wards, :seperatedFromTheGroup, :duel, :neutralPartyCaptured, :allyCaptured].sample}
  symbol :progress, default: :departure

  before :create do
    trace_journeys_path
    self.chapters = [TheCall.new]
  end

  before :save do
    check_progress
    assign_character_roles
  end

  # Adds three sectors along the hero's path, each a little further from the last.
  def trace_journeys_path
    origin = sectors.last
    return unless origin
    3.times do |i|
      c = coordinates_on_box(origin, 2 + i, 3 + i, 1).first
      next unless c
      sectors << (Sector.at(c) || Sector.create(coordinates: c))
    end
  end
  def assign_character_roles
    role << [:mentor, :sidekick, :skeptic, :logical, :foil, :underdog].sample if characters.count < role.count
  end
  # The part a character plays in this journey (protagonist, mentor, ...)
  def role_of(character)
    i = characters.to_a.index(character)
    role[i] if i
  end
  def check_progress
    self.progress = case chapters.size
    when 0...2
      :departure
    when 3...5
      (self.progress == :departure and random(3) == 1) ? (:departure) : (:departed)
    when 5...7
      :initiation
    when 8...12
      (self.progress == :initiation and random(3) == 1) ? (:initiation) : (:initiated)
    when 13..14
      :returning
    when 15..16
      (self.progress == :returning or random(5) == 4) ? (:returning) : (:returned)
    else
      :returned
    end
  end
  def create_chapter
    Generate.chapter(self, progress)
  end

  after :create do
    tell_story
  end

  def tell_story
    hero = characters.first
    where = hero && hero.location && hero.location.sector
    puts "Once upon a time#{where ? ", in #{where.name} #{where.coordinates}" : ''}, our hero#{hero ? "; #{hero.name}" : ''} was just going about their day when #{herald.to_s.humanize} happened."
    puts "In an epic struggle against #{conflict}, our heroes faces a #{nemesis} planning #{plot.to_s.humanize}."
    chapters.each { |c| c.tell_story }
  end
end

class Chapter
  include GameModel
  include Challenge
  belongs_to :journey, required: false
  property :event_index, Integer, required: false

  # the journey's event this chapter plays out in
  def event
    journey && journey.events.to_a[event_index.to_i]
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