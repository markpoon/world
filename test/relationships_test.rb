require 'test_helper'

# Real foreign keys and real join tables (no ids hidden inside JSON columns).
class RelationshipsTest < WorldTest
  def tile; @tile ||= start_tile; end

  # ---- one-to-many ---------------------------------------------------------
  def test_location_has_buildings_users_characters_and_events
    farm = Farm.create(location: tile)
    event = Event.create(location: tile)
    user = make_user
    local = Character.create(location: tile)
    fresh = Location.get(tile.id)
    assert_includes fresh.places, farm
    assert_includes fresh.events, event
    assert_includes fresh.users, user
    assert_includes fresh.characters.map(&:id), local.id
    assert_equal tile.id, farm.location_id
  end

  def test_buildings_have_owners_residents_and_employees
    owner = Character.create(location: tile)
    farm = Farm.create(location: tile, owner: owner)
    assert_includes owner.holdings, farm

    resident = Character.create(location: tile, residence: farm)
    worker = Character.create(location: tile, employed: farm)
    assert_includes farm.residents, resident
    assert_includes farm.employees, worker
  end

  def test_families_and_factions
    family = Guild.create
    member = Character.create(family: family)
    assert_includes family.characters, member
    assert_match(/\AThe .+ Guild\z/, family.fullname)

    faction = Monarchy.create(prefix: :Red)
    ruled = Character.create(allegience: faction)
    assert_includes faction.subjects, ruled
    assert_equal faction.id, ruled.allegience_id

    vassal = Monarchy.create(master: Empire.create)
    assert_instance_of Empire, vassal.master
  end

  def test_spouse_is_a_reference_to_another_character
    a = Character.create
    b = Character.create(spouse: a)
    assert_equal a, b.spouse
  end

  # ---- items belong to a character or to a building ------------------------
  def test_a_character_owns_items
    user = make_user
    character = user.characters.first
    assert_operator character.items.size, :>, 0
    character.items.each { |item| assert_equal character.id, item.character_id; assert_nil item.place_id }
  end

  def test_a_building_can_hold_items
    shop = Market.create(location: tile)
    sword = Sword.create
    shop.items << sword
    shop.save
    assert_equal shop.id, Item.get(sword.id).place_id
    assert_nil Item.get(sword.id).character_id
    assert_includes Market.get(shop.id).items, Item.get(sword.id)
  end

  def test_buildings_without_an_inventory_have_no_items_relationship
    refute Hall.new.respond_to?(:items)
  end

  # ---- tasks ---------------------------------------------------------------
  def test_events_have_tasks_and_tasks_have_subtasks
    event = Event.create(location: tile)
    task = Courier.create(event: event)
    sub = Combat.create(parent: task)
    assert_includes Event.get(event.id).tasks.map(&:id), task.id
    assert_includes Task.get(task.id).tasks.map(&:id), sub.id
    assert_equal task, sub.parent
  end

  def test_a_task_can_point_at_any_record
    task = Procure.create
    task.target = tile
    task.save
    assert_equal tile.id, Task.get(task.id).target.id
    assert_equal 'Plain', Task.get(task.id).target_type
  end

  def test_a_courier_remembers_its_destination_tile
    courier = Deliver.create
    courier.destination = tile
    courier.save
    assert_equal tile.id, Courier.get(courier.id).destination.id
    assert_nil Deliver.create.destination
  end

  # ---- journeys ------------------------------------------------------------
  def test_journeys_have_chapters
    journey = new_journey # starts with its first chapter, The Call
    chapter = Aid.create(journey: journey)
    chapters = Journey.get(journey.id).chapters.map(&:class)
    assert_includes chapters, TheCall
    assert_includes chapters, Aid
    assert_equal journey, chapter.journey
  end

  def test_objectives_belong_to_a_family_or_faction_and_point_at_an_event
    family = Guild.create
    faction = Monarchy.create
    event = Event.create
    family_goal = Objective.create(family: family, event: event)
    faction_goal = Objective.create(faction: faction)
    assert_includes family.objectives, family_goal
    assert_includes faction.objectives, faction_goal
    assert_equal event, family_goal.event
    refute_includes faction.objectives, family_goal
  end

  # ---- many-to-many (join tables) ------------------------------------------
  def test_characters_and_journeys
    hero = Character.create
    journey = new_journey
    hero.journeys << journey
    assert hero.save
    assert_includes Character.get(hero.id).journeys, journey
    assert_includes Journey.get(journey.id).characters, hero
  end

  def test_events_and_journeys
    event = Event.create
    journey = new_journey
    journey.events << event
    assert journey.save
    assert_includes Event.get(event.id).journeys, journey
  end

  def test_characters_can_have_many_abilities_shared_between_characters
    ability = Ability.create(name: 'Shout')
    a = Character.create
    b = Character.create
    [a, b].each { |c| c.abilities << ability; c.save }
    assert_equal [ability.id], Character.get(a.id).abilities.map(&:id)
    assert_equal [ability.id], Character.get(b.id).abilities.map(&:id)
  end

  def test_parents_and_children
    mother = Character.create
    father = Character.create
    child = Character.create
    child.progenitors << mother
    child.progenitors << father
    assert child.save
    assert_equal [mother.id, father.id].sort, Character.get(child.id).progenitors.map(&:id).sort
    assert_equal [child.id], Character.get(mother.id).progeny.map(&:id)
  end

  def test_a_character_cannot_have_more_than_two_parents
    child = Character.create
    3.times { child.progenitors << Character.create }
    refute child.save
    assert_includes child.errors.to_a.flatten.join, 'more than two parents'
  end

  def test_sectors_factions_and_journeys_use_join_tables
    sector = Sector.create(cx: 1.0, cy: 1.0)
    faction = Monarchy.create
    sector.factions << faction
    assert sector.save
    assert_includes Faction.get(faction.id).sectors, sector

    journey = new_journey
    journey.sectors << sector
    journey.objectives << Objective.create
    assert journey.save
    assert_equal 1, Journey.get(journey.id).sectors.size
    assert_equal 1, Journey.get(journey.id).objectives.size
  end

  def test_no_relationship_is_stored_as_a_json_array_of_ids
    json_columns = DataMapper::Model.descendants.flat_map do |model|
      model.properties.select { |p| p.is_a?(DataMapper::Property::Json) }.map { |p| "#{model.name}##{p.name}" }
    end.uniq
    json_columns.each { |c| refute_match(/_ids\z/, c) }
  end

  # ---- character rules -----------------------------------------------------
  def test_a_user_cannot_exceed_their_character_slots
    user = make_user # gets one character on sign-up; slots default to 1
    extra = Character.new(user: user)
    refute extra.save
    assert_includes extra.errors.to_a.flatten.join, 'enough slots'
  end

  def test_a_character_without_a_user_is_fine
    assert Character.create.saved?
  end
end
