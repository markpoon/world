module Taskable
  def self.included base 
    base.class_eval do
      property :target_id, Integer, required: false   # what this event/task is about
      property :target_type, String, required: false, length: 255 # ...and which kind of record that is
      property :completed, Boolean, required: false
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
    tasks.collect{|task| task.to_s }.join('. ') unless tasks.empty?
  end
    
  def complete
    if complete? and completed
      after_complete
      self.completed = true
    end
  end
  def complete?
    progress = 0 if progress.nil?
    if (tasks.empty? and progress >= 100) or (tasks.all?(&:complete?) and progress >= 100)
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
    self.target_id = target.id
    self.target_type = target.class.to_s
  end
  def target
    return if target_id.nil? || target_type.nil?
    target_type.constantize.get(target_id)
  end
end

class Event
  include GameModel
  include Challenge
  include Taskable
  has n, :tasks
  belongs_to :location, required: false
  has n, :journeys, through: DataMapper::Resource
  after_build do
    generate_tasks
    add_reward
    add_npc
  end
  before :save do
    complete if complete?
  end
  def characters
    journeys.collect(&:characters).flatten.compact.uniq
  end
  def to_s
    where = location ? "#{location.class}#{location.coordinates}" : "an unknown place"
    reply = ["At #{where}, a #{self.class} event is occuring"]
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
  property :count, Integer, required: false, default: proc { |_r, _p| random 10 }
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
  after_build do
    if target.nil? and location and location.sector
      self.target = location.sector.locations.sample
    end
  end
  after :update do
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
  property :place, String, required: false, length: 255, default: proc { |_r, _p| ["House", "Home", "Farm"].sample }
  @tasks_default = random(6).times.collect{['Resourcing', 'Courier'].sample}
  def complete
  end
end
class Urban < Event
end
class UrbanPlace <  Event
  after_build do
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
  include GameModel
  include Taskable
  # a task belongs to an event, or is a sub-task of another task
  belongs_to :event, required: false
  belongs_to :parent, 'Task', required: false
  has n, :tasks, 'Task', child_key: [:parent_id]
  property :progress, Integer, required: false
  after_build do
    generate_tasks
  end
  def complete?
    !progress.nil? && progress > 100
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
    phrase << progress_text
    unless tasks.empty?
      phrase << "it has tasks: "
      phrase << self.tasks.collect(&:to_s)
    end
    phrase.join(', ')
  end
  def progress_text
    "and is #{progress || 0}% complete."
  end
end

class Resourcing < Task
  property :count, Integer, required: false, default: proc { |_r, _p| random 25 }
  symbol :resource, default: proc { |_r, _p| [:wood, :ore, :food, :water].sample }

  before :create do
    self.target = parent || event
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
  property :item, String, required: false, length: 255 # the kind of item to craft
  before :create do
    self.item = Item.descendant_classes.sample.to_s
  end
  def after_complete
    Generate.item(item.constantize)
  end
end

class Courier < Task
  list :destination_coordinates
  def destination=(location); self.destination_coordinates = location.coordinates; end
  def destination; Location.at(destination_coordinates) unless destination_coordinates.empty?; end
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
  property :entities, Integer, required: false
end
class Negotiation < Diplomacy
  # def to_s
  #   "#{self.class} between #{self.entities.join(', ')||'entities not found'}"
  # end
end
class Embargo < Diplomacy
  # an order of a government prohibiting the departure of commercial ships and 
  # other vehicles from its ports. It is a legal prohibition on commerce.
  symbol :prohibits, default: proc { |_r, _p| [:food, :ore, :wood, :items].sample }
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
  property :open, Boolean, required: false, default: true
  # def to_s
  #   "#{open? ? ("Open") : ("Closed")} #{self.class} between #{self.entities} to #{self.target}"
  # end
end
class Tariff < Treaty
  symbol :goods, default: proc { |_r, _p| [:food, :ore, :wood, :items].sample }
  property :tax, Integer, required: false, default: proc { |_r, _p| random(1,5) }
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
  property :count, Integer, required: false, default: proc { |_r, _p| random 5, 10 }
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