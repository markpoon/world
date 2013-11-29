class Family
  include Mongoid::Document
  include Mongoid::Timestamps::Created
  include Naming
  include Ambition
  has_many :characters
  has_many :places
  belongs_to :faction
  
  field :n, as: :name, type: String
  field :s, as: :speciality, type: Symbol
  
  after_initialize do
    unless persisted?
      self.name = random_person_name :family
      specialize if speciality.nil?
    end
  end
  def specialize
    puts "base classes cannot specialize"
  end
  def locations
    self.places.collect{|i|i.location}.uniq
  end
  def fullname
    "The #{name} #{self.class}"
  end
  
end
class Guild < Family
  def specialize
    self.speciality = [:food, :wood, :ore, :gold, :item, :construction].sample
  end
end
class Band < Family
  def specialize
    self.speciality = [:combat, :trade, :gold, :item].sample
  end
end
class Clan < Family
  def specialize
    self.speciality = [:food, :wood, :ore, :gold].sample
  end
end