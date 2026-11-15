
class User
  include DataMapper::Resource
  include Entity
  include Targetting
  PUBLIC_JSON = {:only => [:_id, :n, :faction_id], :methods => [:vision, :coordinates]}

  has_many :characters, dependent: :nullify
  belongs_to :faction, dependent: :nullify
  
  field :e, as: :email, type: String
  field :s, as: :salt, type: String
  field :h, as: :hashed_password, type: String
  
  # Real validations (the Mongoid-era declarations are no-ops under DataMapper):
  # an account always has a start tile, an email and a password hash.
  [[:location, ->(u) { u.location }], [:email, ->(u) { u.email }],
   [:hashed_password, ->(u) { u.hashed_password }]].each do |attr, getter|
    validates_with_block(attr) do
      getter.call(self).to_s.empty? && !getter.call(self).respond_to?(:id) ? [false, "#{attr} must not be blank"] : true
    end
  end
  validates_with_block(:email) do
    User.normalize_email(email) =~ /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/ ? true : [false, 'email is not valid']
  end
  
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
  # Emails are case-insensitive: store them trimmed and lower-cased.
  def self.normalize_email(email); email.to_s.strip.downcase; end
  def email=(value); super(User.normalize_email(value)); end

  # New passwords are hashed with bcrypt (slow, salted, built for passwords).
  # `salt` stays as a column for accounts created before the upgrade.
  BCRYPT_COST = 10
  def password=(pass)
    @password = pass
    self.salt = User.random_string(15) unless self.salt
    self.hashed_password = BCrypt::Password.create(pass.to_s, cost: BCRYPT_COST).to_s
  end
  def bcrypt_hash?; hashed_password.to_s.start_with?('$2'); end

  def self.authenticate(email, pass)
    u = User.find_by(email: User.normalize_email(email))
    return nil if u.nil?
    pass = pass.to_s
    if u.bcrypt_hash?
      return (BCrypt::Password.new(u.hashed_password) == pass ? u : nil)
    end
    # Accounts from before the bcrypt upgrade: check the old salted SHA-256,
    # and move the account to bcrypt as soon as the password is proven.
    return nil unless User.encrypt(pass, u.salt.to_s) == u.hashed_password
    u.password = pass
    u.save
    u
  end
  def sight
    # make sure the map around the player (and their characters) exists
    World.ensure_area(*location.coordinates, vision + 1)
    characters.each { |c| World.ensure_area(*c.location.coordinates, (c.vision || 1) + 1) if c.location }
    response = {}
    response["users"] = [self.as_json]
    visible = (self.characters.collect(&:sight) << super).flatten.compact.uniq
    World.preload_places(visible)
    response["locations"] = visible.as_json
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