
class Sector
  include Mongoid::Document
  include Coordinates
  has_many :locations
  has_and_belongs_to_many :factions
  validates_length_of :locations, minimum: 100, maximum: 100
  validates_presence_of :locations
  field :p, as: :prefix, type: Symbol
  field :s, as: :suffix, type: Symbol
  def name
    [prefix, suffix].map(&:to_s).join(" ")
  end
  def set_name
    self.prefix = [["Aber","Ast","Auch","Ach","Bal","Brad","Car","Caer","Din","Dinas","Gill","Kin","King","Kirk","Lan","Lhan","Llan","Lang","Lin","Pit","Pol","Pont","Stan","Tre","Win","Whel"], ["shire","mire","more","wick","dale","ay","ey","y","bourne","burn","brough","burgh","bury","by","carden","cardine","don","den","field","forth","ghyll","ham","holme","kirk","mere","port","stead","wick"]].map(&:sample).join.intern
    distribution = location_distribution
    self.suffix = case distribution.max_by{|k, v| v}[0]
    when :Plain then [:Plains, :Flats, :Fields, :Grasslands, :Meadows, :Moorland, :Prairie, :Steppe].sample
    when :Forest then [:Forest, :Grove, :Timberlands, :Wildwoods, :Brake, :Chase, :Coppice, :Copse, :Cover, :Bosk, :Orchard].sample
    when *[:Hill, :ForestHill] then [:Foothill, :Hillside, :Mound, :Knoll, :Butte, :Bluff, :Ridge, :Highlands].sample
    when :Mountain then [:Peak, :Mountains, :Mount, :Summit, :Alp, :Sierra, :Cordillera, :Massif].sample
    when :Lake then [:Lake, :Creek, :Pool, :Sluice, :Spring, :Tarn, :Basin].sample
    when :Sea then [:Sea, :Ocean].sample
    end
  end
  def location_distribution
    distribution, location_types = {}, []
    locations.only(:_type).each{|i| location_types << i._type.intern}
    [:Plain, :Forest, :ForestHill, :Hill, :Mountain, :Lake, :Sea].each do |i|
      distribution[i] = location_types.count i
    end
    distribution
  end
  def places
    locations.map(&:places).flatten.compact
  end
  def events
    locations.map(&:events).flatten.compact
  end
  after_create do
    puts "Generated #{self.name}, #{self.coordinates}"
  end
end