class Faction
  include GameModel
  include Naming
  include Ambition
  has n, :sectors, through: DataMapper::Resource
  has n, :families
  has n, :locations
  has n, :subjects, 'Character', child_key: [:allegience_id]
  belongs_to :master, 'Faction', required: false
  symbol :prefix
  def name;"The #{families.empty? ? (self.prefix) : (self.families.first.name)} #{self.class.to_s}";end
  def places; locations.collect(&:places).flatten.compact; end
  def halls; places.select{|i|i._type == "Hall"}; end
  def upkeep;1 * 0.2 ** subjects.count + 1 ** 1.7 ** locations.count;end
  def issueQuest(character)
    current = character.journeys.last
    if current.nil? || current.progress == :returned
      journey = Journey.create
      character.journeys << journey
      character.save
      journey
    else
      puts 'this character has an active journey'
    end
  end
  after :create do
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
  has n, :vassals, 'Faction', child_key: [:master_id]
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
  include GameModel
  include Targetting
  # owned by a family or a faction (see Ambition), and pointing at an event / journey
  belongs_to :family, required: false
  belongs_to :faction, required: false
  belongs_to :event, required: false
  belongs_to :journey, required: false
  property :active, Boolean, required: false, default: true
  def action; active.nil?; end
  def describe
    event.describe
  end
end
