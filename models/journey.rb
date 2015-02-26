class Journey
  include DataMapper::Resource
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
class Chapter
  include DataMapper::Resource
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