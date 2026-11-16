require 'test_helper'

# Game rules that live in the models: items, events, queries, validations.
class ModelsTest < WorldTest
  # ---- items ---------------------------------------------------------------
  def test_item_materials_adjust_quality_and_durability
    gem = Gemstone.new
    assert_equal :crystal, gem.material
    assert_operator gem.quality, :>=, 10 + 4 - 0
    paper = Readable.new
    assert_equal :paper, paper.material
  end

  def test_a_material_list_picks_one_of_the_choices
    10.times { assert_includes %i[iron steel], LockPicks.new.material }
  end

  def test_durability_falls_back_to_the_maximum
    sword = Sword.new
    sword.durability = nil
    assert_equal sword.durability_max, sword.durability
  end

  def test_an_items_portrait_and_name
    sword = Sword.new
    assert_equal 'Sword', sword.name
    assert_match(/\ASword\d+\z/, sword.portrait)
  end

  def test_price_grows_with_quality
    cheap = Sword.new
    cheap.quality = 10
    cheap.durability = nil # undamaged: durability follows the maximum
    dear = Sword.new
    dear.quality = 40
    dear.durability = nil
    assert_operator dear.price, :>, cheap.price
  end

  def test_enchanted_items_price_in_their_charge
    potion = Potion.new
    potion.charge = 8
    assert_operator potion.price, :>, potion.send(:base_price)
  end

  def test_a_key_needs_a_lock
    refute Key.new.save
    assert Key.new(lock: 7).save
  end

  def test_equipping_unequips_the_other_item_in_the_same_slot
    character = make_user.characters.first
    first = Sword.create(character: character)
    second = Dagger.create(character: character)
    [first, second].each { |item| item.update(slot: :hand) }
    first.equip
    second.equip
    assert Item.get(second.id).equipped
    refute Item.get(first.id).equipped
  end

  def test_tools_start_charged_and_a_used_up_item_is_removed
    picks = LockPicks.create
    assert_equal picks.quality, picks.charge
    picks.update(charge: 1)
    picks.send(:use_charge)
    assert_nil Item.get(picks.id)
  end

  def test_using_a_charge_counts_down
    picks = LockPicks.create
    picks.update(charge: 5)
    picks.send(:use_charge)
    assert_equal 4, Item.get(picks.id).charge
  end

  def test_item_class_tree_has_leaf_classes_to_generate
    leaves = Item.descendant_classes.select { |k| k.descendant_classes.empty? }
    assert_includes leaves, Sword
    assert_includes leaves, Potion
    leaves.each { |klass| assert_operator klass, :<, Item }
  end

  # ---- inventory (characters and buildings) ---------------------------------
  def test_a_character_starts_with_gear_suited_to_their_age
    character = make_user.characters.first
    assert_operator character.items.size, :>=, 2
    assert(character.items.any? { |i| i.is_a?(Weapon) })
  end

  def test_gold_defaults_to_a_small_random_amount
    assert_includes 1..42, Character.new.gold
    assert_includes 1..42, Inn.new.gold
  end

  # ---- characters ----------------------------------------------------------
  def test_gender_and_sexuality_helpers
    c = Character.new
    c.gender = :female
    assert_equal :female, c.gender
    assert c.female?
    c.gender = :male
    assert_equal :male, c.gender
    c.sexuality = :homosexual
    assert_equal :homosexual, c.sexuality
    c.sexuality = :heterosexual
    assert_equal :heterosexual, c.sexuality
  end

  def test_a_character_gets_a_name_and_a_family_name_comes_from_the_family
    c = Character.new
    refute_empty c.firstname
    assert_equal c.firstname, c.name
    c.family = Guild.create(name: 'Hawthorne')
    assert_equal "#{c.firstname} Hawthorne", c.name
  end

  def test_vision_defaults_to_one
    assert_equal 1, Character.new.vision
    assert_equal 3, Character.new(vision: 3).vision
  end

  def test_stats_and_derived_values
    c = Character.create
    assert_operator c.scratch_max, :>, 0
    assert_operator c.wound_max, :>, 0
    assert_equal c.energy_max, c.energy
    c.update(energy: 12)
    assert_equal 12, c.energy
    assert_includes [true, false], c.check(:strength, 1, 3)
  end

  # ---- events and tasks ----------------------------------------------------
  def test_events_describe_where_they_happen
    tile = start_tile
    event = quietly { Logging.create(location: tile) }
    assert_match(/At Plain\[-79.708, 43.607\], a Logging event is occuring/, event.to_s)
    assert_match(/unknown place/, Logging.new.to_s)
  end

  def test_building_an_event_gives_it_tasks_rewards_and_helpers
    event = Logging.new(location: start_tile)
    refute_empty event.tasks
    assert_operator event.reward.size, :>=, 1
    refute_empty event.npc
  end

  def test_task_descriptions
    task = Procure.new
    assert_match(/procure/i, task.to_s)
    assert_match(/and is 0% complete/, task.to_s)
    task.progress = 50
    assert_match(/and is 50% complete/, task.progress_text)
  end

  def test_a_task_is_complete_above_100_percent_progress
    task = Courier.new
    refute task.complete?
    task.progress = 101
    assert task.complete?
  end

  def test_travelling_events_do_not_need_a_sector
    assert Travellers.new(location: start_tile).save
  end

  def test_event_targets_round_trip
    tile = start_tile
    event = Event.create
    event.target = tile
    event.save
    assert_equal tile.id, Event.get(event.id).target.id
    event.target = nil
    assert_equal tile.id, event.target.id, 'a nil target is ignored'
  end

  def test_crafting_picks_an_item_kind_when_created
    craft = Craft.create
    assert_operator craft.item.constantize, :<, Item
  end

  # ---- queries -------------------------------------------------------------
  def test_within_finds_tiles_inside_the_radius_only
    World.ensure_area(*Seed::CENTER, 5)
    near = Location.within(Seed::CENTER, 0.0015)
    assert_operator near.size, :>, 1
    near.each { |t| assert_operator Math.hypot(t.cx - Seed::CENTER[0], t.cy - Seed::CENTER[1]), :<=, 0.0015 + 1e-9 }
    assert_operator Location.within(Seed::CENTER, 0.0015).size, :<, Location.within(Seed::CENTER, 0.01).size
    assert_equal Location.count, Location.within(Seed::CENTER, 1).size
  end

  def test_within_with_nothing_nearby_is_empty
    assert_empty Location.within([0, 0], 0.001)
  end

  def test_entities_can_be_moved_by_coordinates
    tile = start_tile
    other = World.tile_at(Seed::CENTER[0] + 0.001, Seed::CENTER[1])
    character = Character.create(location: tile)
    quietly { character.move(other.coordinates) }
    assert_equal other.id, character.location.id
  end

  def test_setting_coordinates_builds_the_map_and_places_the_entity
    character = Character.new
    character.coordinates = [10.0, 20.0]
    assert_equal [10.0, 20.0], character.location.coordinates
    assert_equal 1, Location.count
  end

  def test_users_see_the_tiles_around_them
    user = make_user
    ids = user.sight['locations'].map { |l| l['id'] }
    assert_includes ids, user.location.id
  end

  # ---- misc ----------------------------------------------------------------
  def test_a_location_names_its_terrain
    assert_equal :Plain, Plain.new.terrain
    assert_nil Location.new.terrain
  end

  def test_gathering_resources_from_land
    land = Plain.create(cx: 1.0, cy: 1.0, resource: 100)
    farm = Farm.create(food: 10)
    land.give_resource_to(farm, :food)
    assert_equal 99, Land.get(land.id).resource
    assert_equal 11, Farm.get(farm.id).food
  end

  def test_sectors_name_themselves_after_their_commonest_terrain
    sector = Sector.create(cx: 1.0, cy: 1.0)
    3.times { |i| Mountain.create(cx: 1.0 + i / 1000.0, cy: 1.0, sector: sector) }
    Plain.create(cx: 1.5, cy: 1.0, sector: sector)
    quietly { sector.set_name }
    assert_includes %i[Peak Mountains Mount Summit Alp Sierra Cordillera Massif], sector.suffix
    refute_empty sector.name
  end

  def test_the_random_helper
    20.times { assert_includes 1..5, random(5) }
    20.times { assert_includes 3..4, random(3, 4) }
  end
end
