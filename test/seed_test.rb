require 'test_helper'

class SeedTest < WorldTest
  def test_demo_user_is_created_with_a_map_and_a_character
    user = quietly { Seed.demo_user! }
    assert_equal Seed::DEMO_EMAIL, user.email
    assert_equal Seed::CENTER, user.location.coordinates
    assert_operator Location.count, :>=, (2 * Seed::RADIUS + 1)**2
    assert_equal 1, user.characters.count
  end

  def test_demo_user_logs_in_with_the_published_password
    quietly { Seed.demo_user! }
    assert User.authenticate(Seed::DEMO_EMAIL, Seed::DEMO_PASSWORD)
  end

  def test_seeding_twice_changes_nothing
    first = quietly { Seed.demo_user! }
    tiles = Location.count
    second = quietly { Seed.demo_user! }
    assert_equal first.id, second.id
    assert_equal 1, User.count
    assert_equal tiles, Location.count
    assert_equal 1, Character.count
  end

  def test_the_starting_map_is_built_without_a_user
    assert_operator Seed.starting_map!, :>, 0
    assert_equal 0, User.count
  end

  def test_demo_user_is_only_seeded_on_boot_when_asked
    with_env('SEED_DEMO_USER' => nil) { refute AppEnv.seed_demo_user? }
    with_env('SEED_DEMO_USER' => 'true') { assert AppEnv.seed_demo_user? }
  end
end
