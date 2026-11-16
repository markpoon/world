require 'test_helper'

class UserTest < WorldTest
  # ---- emails --------------------------------------------------------------
  def test_normalize_email_trims_and_lowercases
    assert_equal 'a@b.com', User.normalize_email("  A@B.Com \n")
    assert_equal '', User.normalize_email(nil)
  end

  def test_the_email_is_stored_normalized
    assert_equal 'mixed@example.com', make_user('  Mixed@Example.COM ').email
  end

  # ---- passwords -----------------------------------------------------------
  def test_passwords_are_hashed_with_bcrypt_never_stored_in_clear
    user = make_user
    assert user.bcrypt_hash?
    refute_includes user.hashed_password, 'a good passphrase'
    assert_match(/\A\$2[aby]\$/, user.hashed_password)
  end

  def test_the_same_password_hashes_differently_each_time
    refute_equal make_user('one@example.com', 'same phrase!').hashed_password,
                 make_user('two@example.com', 'same phrase!').hashed_password
  end

  def test_authenticate_accepts_the_right_password
    user = make_user
    assert_equal user.id, User.authenticate('player@example.com', 'a good passphrase').id
  end

  def test_authenticate_is_case_insensitive_about_the_email
    user = make_user
    assert_equal user.id, User.authenticate('  PLAYER@Example.com ', 'a good passphrase').id
  end

  def test_authenticate_rejects_a_wrong_password_unknown_email_and_blanks
    make_user
    assert_nil User.authenticate('player@example.com', 'wrong')
    assert_nil User.authenticate('nobody@example.com', 'a good passphrase')
    assert_nil User.authenticate('', '')
    assert_nil User.authenticate(nil, nil)
  end

  def test_a_legacy_sha256_account_can_log_in_and_is_upgraded_to_bcrypt
    user = make_user('old@example.com', 'placeholder')
    user.salt = 'legacy-salt'
    user.hashed_password = User.encrypt('old passphrase', 'legacy-salt')
    user.save
    refute User.get(user.id).bcrypt_hash?

    assert_nil User.authenticate('old@example.com', 'not the passphrase')
    refute User.get(user.id).bcrypt_hash?, 'a failed login must not change the hash'

    assert_equal user.id, User.authenticate('old@example.com', 'old passphrase').id
    assert User.get(user.id).bcrypt_hash?
    assert User.authenticate('old@example.com', 'old passphrase'), 'still works after the upgrade'
  end

  # ---- validations ---------------------------------------------------------
  def test_a_user_needs_an_email
    user = User.new(email: '', password: 'a good passphrase')
    user.location = start_tile
    refute user.save
    assert_equal 0, User.count
  end

  def test_a_user_needs_a_well_formed_email
    ['nope', 'a@b', '@example.com', 'a b@example.com'].each do |bad|
      user = User.new(email: bad, password: 'a good passphrase')
      user.location = start_tile
      refute user.save, "#{bad.inspect} should be rejected"
    end
  end

  def test_a_user_needs_a_start_tile
    refute User.new(email: 'x@example.com', password: 'a good passphrase').save
  end

  def test_a_valid_user_saves
    assert make_user.saved?
    assert_equal 1, User.count
  end

  # ---- what a new player gets ------------------------------------------------
  def test_a_new_user_gets_a_character_that_is_not_standing_in_water_or_on_a_mountain
    user = make_user
    chars = User.get(user.id).characters.to_a
    assert_equal 1, chars.size
    refute_includes [Sea, Lake, Mountain], chars.first.location.class
  end

  def test_sight_returns_users_locations_and_characters
    user = make_user
    seen = JSON.parse(user.sight.to_json)
    assert_equal %w[characters locations users], seen.keys.sort
    assert_operator seen['locations'].size, :>, 20
    assert_equal user.email, seen['users'].first['email'] if seen['users'].first.key?('email')
    assert_equal 1, seen['characters'].size
  end

  def test_sight_never_leaks_credentials
    json = make_user.sight.to_json
    refute_includes json, 'hashed_password'
    refute_includes json, 'bcrypt'
    refute_includes json, 'a good passphrase'
  end

  def test_sight_builds_missing_map_around_the_player
    user = make_user
    Location.all.destroy
    refute_empty user.sight['locations']
    assert_operator Location.count, :>, 0
  end
end
