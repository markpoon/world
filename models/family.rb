class Family
  include GameModel
  include Naming
  include Ambition
  has n, :characters
  has n, :places
  belongs_to :faction, required: false
  
  property :name, String, required: false, length: 255
  symbol :speciality
  
  after_build do
    self.name = random_person_name :family if name.nil?
    specialize if speciality.nil?
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