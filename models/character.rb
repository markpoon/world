module Personality 
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

Effect = Struct.new :name, :duration, :value

class Stats
  include DataMapper::Resource
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

class Character < Stats
  include Mongoid::Timestamps::Created
  include Entity
  include Naming
  include Personality
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
  PUBLIC_JSON = {:except => [:created_at, :x, :q, :n, :ability_ids, :journey_ids, :f, :location_id, :v], :methods => [:vision, :name, :gender, :coordinates], :include => {:items => Item::PUBLIC_JSON, :abilities=> Ability::PUBLIC_JSON}}
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
