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
  include DataMapper::Resource
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
  PUBLIC_JSON = {:except => :e, :methods => [:durability, :durability_max, :portrait, :price]}
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