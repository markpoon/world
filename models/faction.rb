class Faction
  include DataMapper::Resource
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
  include DataMapper::Resource
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