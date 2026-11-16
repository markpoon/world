
class Ability
  include GameModel
  
  property :name, String, required: false, length: 255
  property :range, Integer, required: false
  property :area, Integer, required: false
  
  symbol :effect
  property :value, Integer, required: false
  property :duration, Integer, required: false
  
  symbol :cost_type
  property :cost, Integer, required: false

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
  def as_json(*)
    serialize(:id, :name, :range, :area, :effect, :value, :duration, :cost_type, :cost)
  end
  private
  def affect(target)
    target.send(effect, value, duration)
  end
end