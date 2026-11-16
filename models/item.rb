module Inventory
  def self.included(reciever)
    reciever.class_eval do
      property :gold, Integer, required: false, default: proc { |_r, _p| random 42 }
      # Items belong to a character or to a building: the foreign key depends on which
      has n, :items, 'Item', child_key: [reciever.name == 'Character' ? :character_id : :place_id]
    end
  end
  def buys(item, seller)
    if item.price < self.gold
      self.gold -= item.price
      self.gets seller.items.pop
      seller.gold += item.price
      [self, seller].each(&:save)
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
    items = Array(items).compact
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
      has n, :abilities, through: DataMapper::Resource
    end
  end
      
  def charge_max
    l = self.durability
    if [:wood, :leather].include?(self.material)
      l *= 2
    else
      l *= 0.7
    end
    if respond_to?(:slot) and [:finger, :neck, :head].include?(self.slot)
      l *= 1.5
    else
      l *= 0.7
    end
    l.round
  end
  def price
    base_price + ((charge || 0).to_f / [charge_max, 1].max * 4)
  end
  private
  def use_item; puts "it's magical!"; true; end
end

class Item
  include GameModel
  belongs_to :character, required: false
  belongs_to :place, required: false
  
  symbol :material
  property :quality, Integer, required: false, default: proc { |_r, _p| random 10,24 }
  property :durability, Integer, required: false, default: proc { |_r, _p| random 10,24 }
  
  symbol :effect
  property :charge, Integer, required: false
  property :enchanted, Boolean, required: false
  
  after_build do
    self.class.send(:include, Enchanted) if enchanted
  end
  
  def material=(choice)
    choice = choice.sample if choice.is_a?(Array)
    super(choice)
    case material
    when :crystal
      self.quality += random(4,8)
      self.durability -= random(6,9)
    when :glass, :paper
      self.quality += random(2,6)
      self.durability -= random(5,8)
    when :gold, :silver
      self.quality += random(3,5)
      self.durability -= random(3,4)
    when :wood, :leather
      self.quality -= random(3,7)
      self.durability -= random(1,2)
    when :iron, :steel
      self.durability += random(5,8)
    end
  end

  def durability
    attribute_get(:durability) || durability_max
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
    l.round
  end
  
  def name; self.class.to_s; end
  def portrait; name + (durability / 10 + 1).to_s; end
  def price; base_price; end
  def use; use_charge if use_item; end
  def as_json(*)
    serialize(:id, :_type, :name, :material, :quality, :durability, :durability_max, :portrait, :price,
              :effect, :charge, :enchanted)
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
    p * (durability.to_f / durability_max)
  end
  def use_charge; charge > 1 ? (self.inc(:charge, -1)) : (self.destroy); end
  def use_item; puts "you used an item!"; false; end
  def location
    character.location
  end 
end

class Gemstone < Item
  after_build do
    unless self.material then self.material = :crystal end
  end
end

class Readable < Item
  after_build do
    unless self.material then self.material = :paper end
  end
  property :read, String, required: false, length: 255
end

class Tool < Item
  before :create do
    self.charge = quality
  end
end

class LockPicks < Tool
  after_build do
    unless self.material then self.material = [:iron, :steel] end
  end
  private
  def use_item(obj)
    obj.send(:unlock)
  end
end

class FlintAndSteel < Tool
  after_build do
    unless self.material then self.material = :steel end
  end
  private
  def use_item(target)
    target.send(:burn)
  end
end

class Potion < Item
  after_build do
    unless self.material then self.material = :glass end
  end
  include Enchanted
  symbol :attribute
  def use_item
  end
end

class Rune < Item
  include Enchanted
  after_build do
    unless self.material then self.material = [:paper, :leather] end
  end
  def use_item(target)
    destroy if abilities.first && abilities.first.use(target, charge)
  end  
end

class Key < Item
  after_build do
    unless self.material then self.material = [:wood, :iron, :steel] end
  end
  property :lock, Integer, required: false
  validates_presence_of :lock
  def unlock(obj)
    obj.id == lock ? (obj.send(:unlock)) : (puts "This key does not unlock this object")
  end
end

class Equipment < Item
  symbol :slot
  property :equipped, Boolean, required: false
  
  # One equipped item per slot: unequip the others in that slot, then equip this one.
  def equip
    if character_id
      Equipment.all(character_id: character_id, slot: slot, equipped: true, :id.not => id).each do |other|
        other.update(equipped: nil)
      end
    end
    update(equipped: true)
  end
end

class Weapon < Equipment
  before :create do
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
  after_build do
    unless self.material then self.material = [:wood, :iron, :steel, :silver, :gold] end
  end
end

class Axe < Weapon
  @damage = 4
  after_build do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class Sword < Weapon
  @damage = 5
  after_build do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class Dagger < Weapon
  @damage = 3
  after_build do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class Mace < Weapon
  @damage = 4
  after_build do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class Bow < Weapon
  @damage = 3
  @range = 5
  include RangedWeapon
  after_build do
    unless self.material then self.material = :wood end
  end
end

class Sling < Weapon
  include RangedWeapon
  @damage = 2
  @range = 3
  after_build do
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
  after_build do
    unless self.material then self.material = :wood end
  end
end

class MetalShield < Armor
  @defense = 2
  after_build do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class BodyArmor < Armor
end

class LeatherArmor < BodyArmor
  @defense = 2
  after_build do
    unless self.material then self.material = :leather end
  end
end

class Chainmail < BodyArmor 
  @defense = 3
  after_build do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class PlateArmor < BodyArmor
  @defense = 4
  after_build do
    unless self.material then self.material = [:iron, :steel, :silver, :gold] end
  end
end

class HeadArmor < Armor
  @defense = 1
  after_build do
    unless self.material then self.material = [:leather, :iron, :steel] end
  end
end

class Accessory < Equipment
  after_build do
    unless self.material then self.material = [:leather, :iron, :steel, :silver, :gold] end
  end
end

class Ring < Accessory
  after_build do
    unless self.material then self.material = [:silver, :gold] end
  end
end

class Necklace < Accessory
  after_build do
    unless self.material then self.material = [:leather, :silver, :gold] end
  end
end