
class User
  include Mongoid::Document
  include Entity
  include Targetting
  PUBLIC_JSON = {:only => [:_id, :n, :faction_id], :methods => [:vision, :coordinates]}

  has_many :characters, dependent: :nullify
  belongs_to :faction, dependent: :nullify
  
  field :e, as: :email, type: String
  field :s, as: :salt, type: String
  field :h, as: :hashed_password, type: String
  
  validates_presence_of :location, :email, :salt, :hashed_password
  
  field :n, as: :energy, type: Integer, default: ->{random 15, 30}
  field :v, as: :vision, type: Integer
  
  field :l, as: :slots, type: Integer
    
  def vision; self.v||5;end
  def slots;self.l||1;end
  def nearby_location(distance = 5)
    potential_locations = (locations_in_circle self.location, distance).all.sample(15)
    candidate_location = potential_locations.pop
    while potential_locations.length > 0 and ![Sea, Lake, Mountain].include? candidate_location.class do
      candidate_location = potential_locations.pop
    end
    candidate_location
  end
  after_create do
    puts "#{self.email} has joined the game, they're at #{self.location.coordinates}"
    # Pony.mail(to: self.email, subject: "Welcome to the Cosmic Dream #{self.email}", body: "Don't forget that your password is \"#{@password}\"")
    self.characters.create!(location: nearby_location)
  end
  def password=(pass)
    @password = pass
    self.salt = User.random_string(15) unless self.salt
    self.hashed_password = User.encrypt(@password, self.salt)
  end
  def self.authenticate(email, pass)
    u = User.find_by(email: email)
    return nil if u.nil?
    return u if User.encrypt(pass, u.salt) == u.hashed_password
    nil
  end
  def sight
    response = {}
    response["users"] = [self.as_json]
    response["locations"] = (self.characters.collect(&:sight) << super).flatten.compact.uniq.as_json
    response["characters"] = self.characters.collect(&:as_json)
    # sectors = (self.characters.collect(&:location).flatten.compact.collect(&:sector).flatten.compact << self.location.sector).uniq
    # locations = sectors.collect(&:locations).flatten.compact
    return response
  end
  def as_json(options = PUBLIC_JSON)
    super(options).reject{|k, v| v.nil?||if v.class == Array then v.empty?; end}
  end
    
  protected
  def self.encrypt(pass, salt)
    Digest::SHA2.hexdigest(pass + salt)
  end
  def self.random_string(len)
    chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
    str = ""
    1.upto(len) { |i| str << chars[Random.new.rand(chars.size-1)] }
    return str
  end
end