
class Ability
  include Mongoid::Document
  
  field :n, as: :name, type: String
  field :r, as: :range, type: Integer
  field :a, as: :area, type: Integer
  
  field :e, as: :effect, type: Symbol
  field :v, as: :value, type: Integer
  field :d, as: :duration, type: Integer
  
  field :t, as: :cost_type, type: Symbol
  field :c, as: :cost, type: Integer

  def teach(character)
    character.abilities << self
  end  

  def use(target=origin, origin)
    return unless #check for range
    if area
      targets = #targets in area
      targets.each{|t| affect t}
    else
      affect target
    end
    origin.inc(cost_type, cost)
  end
  PUBLIC_JSON = {}
  def as_json(options={})
    super(options).reject{|k, v| v.nil?||if v.class == Array then v.empty?; end}
  end
  private
  def affect(target)
    target.send(effect, value, duration)
  end
end