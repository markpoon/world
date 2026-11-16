module Personality 
  def self.included(reciever)
    reciever.class_eval do
      property :indifference, Integer, required: false, default: proc { |_r, _p| random(-15, 15) } # :curiosity, likely to open or play with things vs. not wanting to interact at all.
      property :materialism, Integer, required: false, default: proc { |_r, _p| random(-15, 15) } # :idealism, actions that will be for physical things, gold, items, property  
      property :greed, Integer, required: false, default: proc { |_r, _p| random(-15, 15) } # :naivity, actions that will benefit themselves vs. ones that will benefit the most people.
      property :caution, Integer, required: false, default: proc { |_r, _p| random(-15, 15) } # :spontanaity, How likely a character will choose safe vs. unsafe actions.
      property :stubbornness, Integer, required: false, default: proc { |_r, _p| random(-15, 15) } # :indecisive, stick to previous actions despite negative progress, likelihood to change actions
      property :arrogance, Integer, required: false, default: proc { |_r, _p| random(-15, 15) } # :passive, attempts to take :rep vs. give more :rep to others
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
  include GameModel
  property :wound, Integer, required: false
  property :scratch, Integer, required: false
  property :injury, Integer, required: false
  property :energy, Integer, required: false
  dict :status
  def scratch_max
    (self.resolve + self.dexterity * 1.618 - (self.injury||0)).round
  end  
  def scratch
    scratch_max - (attribute_get(:scratch) || 0)
  end
  def wound_max
    (self.stamina * 3 + self.resolve - (self.injury||0 * 1.618)).round
  end
  def energy_max
    self.intellegence + self.intuition * 2 + self.resolve
  end
  def energy
    attribute_get(:energy) || energy_max
  end
  property :thirst, Integer, required: false, default: proc { |_r, _p| random 80,100 }
  property :hunger, Integer, required: false, default: proc { |_r, _p| random 80,100 }
  property :sleep, Integer, required: false, default: proc { |_r, _p| random 80,100 }
  
  property :strength, Integer, required: false, default: proc { |_r, _p| random 5,15 }
  property :stamina, Integer, required: false, default: proc { |_r, _p| random 5,15 }
  property :dexterity, Integer, required: false, default: proc { |_r, _p| random 5,15 }
  property :persuasion, Integer, required: false, default: proc { |_r, _p| random 5,15 }
  property :intellegence, Integer, required: false, default: proc { |_r, _p| random 5,15 }
  property :intuition, Integer, required: false, default: proc { |_r, _p| random 5,15 }
  property :resolve, Integer, required: false, default: proc { |_r, _p| random 5,15 }

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
  include Entity
  include Naming
  include Personality
  include Prestige
  include Inventory
  include Targetting
  
  belongs_to :user, required: false
  has n, :holdings, 'Place', child_key: [:owner_id]
  belongs_to :employed, 'Place', required: false
  belongs_to :residence, 'Place', required: false
  belongs_to :family, required: false
  belongs_to :spouse, 'Character', required: false
  belongs_to :allegience, 'Faction', required: false

  # parents and children (a character-to-character many-to-many, via Parentage)
  has n, :child_links, 'Parentage', child_key: [:parent_id]
  has n, :parent_links, 'Parentage', child_key: [:child_id]
  has n, :progeny, 'Character', through: :child_links, via: :child
  has n, :progenitors, 'Character', through: :parent_links, via: :parent

  has n, :abilities, through: DataMapper::Resource
  has n, :journeys, through: DataMapper::Resource

  validates_with_method :check_character_limit
  validates_with_method :check_progenitors

  def name; lastname ? ([firstname, lastname].join(' ')) : (firstname); end
  property :firstname, String, required: false, length: 255
  def lastname; self.family ? (self.family.name) : (nil); end

  property :portrait, String, required: false, length: 255
  property :age, Integer, required: false, default: proc { |_r, _p| random 12, 26 }
  property :vision, Integer, required: false
  property :female, Boolean, required: false, default: proc { |_r, _p| [nil, true].sample }
  property :homosexual, Boolean, required: false, default: proc { |_r, _p| [nil, nil, true, nil, nil].sample }
  
  
  symbol :faction_attitude

  symbol :journey_attitude
  
  after_build do
    self.firstname = random_person_name self.gender unless self.firstname
    starting_items if items.empty?
  end
  
  def gender
    self.female? ? (:female) : (:male)
  end
  def gender=(gender)
    self.female = (gender == :female ? true : nil)
  end
  def sexuality
    self.homosexual? ? (:homosexual) : (:heterosexual)
  end
  def sexuality=(sex)
    self.homosexual = (sex == :homosexual ? true : nil)
  end
  def vision
    attribute_get(:vision) || 1
  end
  # What the browser gets for a character.
  def as_json(*)
    serialize(:id, :name, :firstname, :age, :gender, :vision, :coordinates, :gold, :reputation,
              :energy, :scratch, :thirst, :hunger, :sleep,
              :strength, :stamina, :dexterity, :persuasion, :intellegence, :intuition, :resolve,
              :indifference, :materialism, :greed, :caution, :stubbornness, :arrogance,
              :items, :abilities)
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
  # Validations (DataMapper style: true, or [false, message]).
  def check_character_limit
    return true unless new? && user
    user.characters.count >= user.slots ? [false, "This user does not have enough slots open for a new character"] : true
  end
  def check_progenitors
    progenitors.size > 2 ? [false, "Why does this character have more than two parents?"] : true
  end
end

# Join model for Character#progeny / Character#progenitors
class Parentage
  include DataMapper::Resource
  belongs_to :parent, 'Character', key: true
  belongs_to :child, 'Character', key: true
end
