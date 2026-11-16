require 'test_helper'

# GameModel: what every model gets (ids, timestamps, symbol/list columns, build
# hooks, JSON helper). Uses real models so the database round trip is covered.
class GameModelTest < WorldTest
  def test_every_game_model_includes_game_model_and_none_use_the_old_shim
    [Location, Place, Item, Event, Task, Character, User, Journey, Chapter, Faction, Family, Ability, Sector, Objective].each do |model|
      assert_includes model.ancestors, GameModel, model.name
    end
    refute defined?(MongoidCompat)
    refute defined?(Mongoid)
    refute defined?(Moped)
  end

  def test_ids_timestamps_and_the_inheritance_discriminator
    tile = Plain.create(cx: 1.0, cy: 2.0)
    assert_kind_of Integer, tile.id
    assert_operator tile.created_at, :<=, DateTime.now
    assert_equal 'Plain', tile.type.to_s
    assert_equal 'Plain', tile._type
    assert_equal Plain, Location.get(tile.id).class, 'loads back as the subclass'
  end

  def test_symbol_columns_round_trip_as_symbols
    sword = Sword.create
    sword.update(material: :steel, effect: :flame)
    reloaded = Item.get(sword.id)
    assert_equal :steel, reloaded.material
    assert_equal :flame, reloaded.effect
    assert_nil Item.get(Sword.create.id).effect
  end

  def test_symbol_columns_accept_strings_and_store_text
    sword = Sword.create
    sword.update(effect: 'frost')
    assert_equal :frost, Item.get(sword.id).effect
    assert_equal 'frost', DataMapper.repository.adapter.select('SELECT effect FROM items WHERE id = ?', sword.id).first
  end

  def test_list_defaults_are_not_shared_between_records
    a = Chapter.create
    b = Chapter.create
    a.reward << :potion
    a.save
    assert_equal [:potion], Chapter.get(a.id).reward.map(&:to_sym)
    assert_empty b.reward
    assert_empty Chapter.get(b.id).reward
  end

  def test_list_columns_round_trip
    chapter = Chapter.create
    chapter.update(reward: %w[potion sword], npc: %w[knight])
    assert_equal %w[potion sword], Chapter.get(chapter.id).reward
    assert_equal %w[knight], Chapter.get(chapter.id).npc
  end

  def test_after_build_runs_for_new_records_but_not_when_loading
    calls = 0
    Gemstone.after_build { calls += 1 }
    stone = Gemstone.new
    assert_equal 1, calls
    assert_equal :crystal, stone.material, 'the built-in hook still ran too'
    stone.save
    Gemstone.get(stone.id)
    assert_equal 1, calls
  ensure
    Gemstone.build_hooks.pop
  end

  def test_after_build_hooks_run_from_the_base_class_down
    order = []
    Item.after_build { order << :item }
    Equipment.after_build { order << :equipment }
    Weapon.new
    assert_equal %i[item equipment], order.first(2)
  ensure
    Item.build_hooks.pop
    Equipment.build_hooks.pop
  end

  def test_inc_adds_to_a_column_and_saves
    tile = Plain.create(cx: 1.0, cy: 2.0, resource: 10)
    tile.inc(:resource, -3)
    assert_equal 7, Plain.get(tile.id).resource
    tile.inc(:resource)
    assert_equal 8, Plain.get(tile.id).resource
  end

  def test_inc_treats_a_missing_value_as_zero
    sword = Sword.create
    sword.inc(:charge, 5)
    assert_equal 5, Item.get(sword.id).charge
  end

  def test_descendant_classes_lists_subclasses_not_the_class_itself
    assert_includes Location.descendant_classes, Plain
    assert_includes Location.descendant_classes, Sea
    refute_includes Location.descendant_classes, Location
    assert_empty Plain.descendant_classes
  end

  def test_at_finds_a_record_by_exact_coordinates
    tile = Plain.create(cx: 4.5, cy: 6.25)
    assert_equal tile.id, Location.at([4.5, 6.25]).id
    assert_nil Location.at([4.5, 6.26])
  end

  def test_serialize_drops_nil_and_empty_arrays_and_renames
    user = make_user
    json = user.serialize(:id, :faction_id, c: :coordinates)
    assert_equal %w[c id], json.keys.sort
    assert_equal user.coordinates, json['c']
  end

  def test_serialize_renders_nested_records_with_their_own_json
    user = make_user
    character = user.characters.first
    assert_equal character.items.first.as_json, character.serialize(:items)['items'].first
  end
end
