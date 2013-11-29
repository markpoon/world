class Grid
  include Targetting
  attr_reader :vision
  def initialize(user)
    unless user.class == User
      @user = user
      @characters = user.characters
      @vision = []
      [user, characters].flatten.collect do |entity|
        @vision << view_around(entity)
      end
    else
      puts "#{user} is not an user accessing the grid."
    end
  end
  def view_around(entity)
    locations_in_circle(entity.location, entity.vision).only(:coordinates, :places).entries
  end
end