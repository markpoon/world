require 'test_helper'

# The JSON the browser client (views/script.coffee) reads. Changing these keys
# means changing the client too, so they are pinned here.
class WireFormatTest < WorldTest
  def sight
    JSON.parse(make_user.sight.to_json)
  end

  def assert_keys(json, required, optional = [], what = 'object')
    missing = required - json.keys
    extra = json.keys - required - optional
    assert_empty missing, "#{what} is missing #{missing.inspect}"
    assert_empty extra, "#{what} has unexpected keys #{extra.inspect}"
  end

  def test_top_level
    assert_equal %w[characters locations users], sight.keys.sort
  end

  def test_user
    assert_keys sight['users'].first, %w[coordinates energy id vision], %w[faction_id], 'user'
  end

  def test_character
    character = sight['characters'].first
    assert_keys character,
      %w[age arrogance caution coordinates dexterity energy firstname gender gold greed hunger id
         indifference intellegence intuition items materialism name persuasion reputation resolve
         scratch sleep stamina strength stubbornness thirst vision],
      %w[abilities], 'character'
    assert_includes %w[male female], character['gender']
    assert_equal 2, character['coordinates'].size
  end

  def test_items
    items = sight['characters'].first['items']
    refute_empty items
    items.each do |item|
      assert_keys item, %w[_type durability durability_max id material name portrait price quality],
                  %w[charge effect enchanted], 'item'
    end
  end

  def test_locations
    locations = sight['locations']
    locations.each do |tile|
      assert_keys tile, %w[_type c id], %w[resource places], 'location'
      assert_equal 2, tile['c'].size
      assert_equal tile['_type'] =~ /Lake|Sea/ ? false : true, tile.key?('resource')
    end
  end

  def test_buildings
    buildings = sight['locations'].flat_map { |t| t['places'] || [] }
    refute_empty buildings
    buildings.each do |b|
      assert_keys b, %w[_type id name], %w[title category family_id owner_id wood ore food water gold], 'building'
      assert_equal b['_type'], b['name']
    end
  end

  def test_blank_values_are_left_out_rather_than_sent_as_null
    json = sight.to_json
    refute_includes json, 'null'
    refute_includes json, '[]'
  end
end
