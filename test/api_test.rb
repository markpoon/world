require 'test_helper'

# The HTTP surface, exercised through Rack::Test (cookies and all).
class ApiTest < WorldTest
  include Rack::Test::Methods

  def app; APP; end

  def post_json(path, body, headers = {})
    header 'Content-Type', 'application/json'
    post path, body.is_a?(String) ? body : body.to_json, headers
  end

  def json; JSON.parse(last_response.body); end

  def login_as(email, password)
    authorize email, password
    get '/user/login'
  end

  def signup(email, password = 'a good passphrase', extra = {})
    capture_io { post_json '/user/signup', { email: email, password: password }.merge(extra) }
  end

  # ---- pages ---------------------------------------------------------------
  def test_home_page_serves_the_game_shell_with_versioned_assets
    get '/'
    assert last_response.ok?
    assert_match(/id=['"]cr-stage['"]/, last_response.body)
    assert_match(/lang=['"]en['"]/, last_response.body)
    assert_match %r{/css/style\.css\?v=\d+}, last_response.body
    assert_match %r{/js/script\.js\?v=\d+|/js/script\.js}, last_response.body
    assert_includes last_response.body, 'width=device-width, initial-scale=1'
    refute_match(/maximum-scale|user-scalable=no/, last_response.body)
  end

  def test_home_page_loads_no_third_party_scripts
    get '/'
    last_response.body.scan(/<script[^>]*src=["']([^"']+)/).flatten.each do |src|
      refute_match %r{\Ahttps?://}, src, 'game scripts must be served by the app itself'
    end
  end

  def test_unknown_pages_render_the_404_page
    get '/definitely/not/here'
    assert_equal 404, last_response.status
    assert_includes last_response.body, '404'
  end

  def test_login_menu_renders_a_real_form
    get '/menus', path: 'login'
    assert last_response.ok?
    assert_match(/id=['"]loginForm['"]/, last_response.body)
    assert_match(/type=['"]email['"]/, last_response.body)
    assert_match(/type=['"]password['"]/, last_response.body)
    assert_match(/id=['"]signupButton['"]/, last_response.body)
  end

  def test_other_menus_are_not_available
    get '/menus', path: 'admin'
    assert_equal 404, last_response.status
    get '/menus'
    assert_equal 404, last_response.status
  end

  def test_the_script_routes_serve_compiled_javascript
    %w[script isometric2].each do |name|
      get "/js/#{name}.js"
      assert last_response.ok?, "#{name}.js"
      assert_match %r{javascript}, last_response.content_type
      assert_operator last_response.body.size, :>, 1000
    end
  end

  # ---- status and debug routes ---------------------------------------------
  def test_status_reports_mode_flags_and_counts_without_secrets
    World.ensure_area(*Seed::CENTER, 1)
    get '/status'
    assert last_response.ok?
    assert_match %r{json}, last_response.content_type
    assert_equal 'cosmic-dream', json['app']
    assert_equal 'development', json['environment']
    assert_equal ENV['TEST_DATABASE_URL'] ? 'postgres' : 'sqlite', json['database']
    assert_equal 9, json['tiles']
    assert_equal %w[debug_routes load_overture reload_code seed_demo_user show_errors], json['flags'].keys.sort
    refute_includes last_response.body, 'DATABASE_URL'
    refute_includes last_response.body.downcase, 'secret'
  end

  def test_debug_routes_are_not_mounted_when_the_flag_is_off
    get '/binding'
    assert_equal 404, last_response.status
    get '/debug/error'
    assert_equal 404, last_response.status
  end

  # ---- sign up -------------------------------------------------------------
  def test_signup_creates_an_account
    signup 'New.Person@Example.com'
    assert_equal 201, last_response.status
    assert_equal 'new.person@example.com', json['email']
    assert json['id']
    assert_equal 1, User.count
  end

  def test_signup_does_not_expose_the_password_or_hash
    signup 'quiet@example.com'
    refute_includes last_response.body, 'a good passphrase'
    refute_includes last_response.body, 'hashed'
  end

  def test_signup_rejects_malformed_json
    post_json '/user/signup', '{not json'
    assert_equal 400, last_response.status
    assert json['errors']
  end

  def test_signup_rejects_a_json_body_that_is_not_an_object
    post_json '/user/signup', '[1,2,3]'
    assert_equal 422, last_response.status
  end

  def test_signup_validates_the_email
    ['', 'nope', 'a@b', 'two words@example.com', 'x' * 250 + '@example.com'].each do |bad|
      signup bad
      assert_equal 422, last_response.status, bad.inspect
      assert_includes json['errors'].join, 'email'
    end
    assert_equal 0, User.count
  end

  def test_signup_validates_the_passphrase_length
    signup 'short@example.com', 'seven77'
    assert_equal 422, last_response.status
    assert_includes json['errors'].join, '8 characters'

    signup 'long@example.com', 'x' * 129
    assert_equal 422, last_response.status
    assert_includes json['errors'].join, 'too long'

    signup 'ok@example.com', 'x' * 128
    assert_equal 201, last_response.status
  end

  def test_signup_reports_every_problem_at_once
    signup 'bad', 'x'
    assert_equal 2, json['errors'].size
  end

  def test_signup_rejects_a_duplicate_email_in_any_letter_case
    signup 'dup@example.com'
    signup 'DUP@example.com'
    assert_equal 422, last_response.status
    assert_includes json['errors'].join, 'already registered'
    assert_equal 1, User.count
  end

  def test_signup_places_the_player_at_the_given_coordinates_or_the_default_start
    signup 'default@example.com'
    assert_equal Seed::CENTER, User.first(email: 'default@example.com').location.coordinates

    signup 'bogus@example.com', 'a good passphrase', coordinates: [500, 500]
    assert_equal 201, last_response.status
    assert_equal Seed::CENTER, User.first(email: 'bogus@example.com').location.coordinates

    signup 'text@example.com', 'a good passphrase', coordinates: %w[abc def]
    assert_equal 201, last_response.status
  end

  def test_signup_uses_valid_coordinates_and_builds_the_map_there
    signup 'far@example.com', 'a good passphrase', coordinates: [10.5, 20.25]
    assert_equal 201, last_response.status
    assert_equal [10.5, 20.25], User.first(email: 'far@example.com').location.coordinates
    assert World.tile_at(10.5, 20.25)
  end

  def test_signup_is_rate_limited_per_address
    Sphere::SIGNUP_LIMIT.times { |i| signup "user#{i}@example.com" }
    assert_equal 201, last_response.status
    signup 'one.too.many@example.com'
    assert_equal 429, last_response.status
    assert_equal Sphere::SIGNUP_LIMIT, User.count
  end

  def test_invalid_signups_do_not_use_up_the_rate_limit
    (Sphere::SIGNUP_LIMIT + 3).times { signup 'bad' }
    signup 'fine@example.com'
    assert_equal 201, last_response.status
  end

  # ---- login ---------------------------------------------------------------
  def test_login_without_credentials_is_a_bad_request
    get '/user/login'
    assert_equal 400, last_response.status
  end

  def test_login_with_a_wrong_password_is_unauthorized_and_sets_no_session
    make_user
    login_as 'player@example.com', 'wrong'
    assert_equal 401, last_response.status
    get '/user/sight'
    assert_equal 401, last_response.status
  end

  def test_login_returns_the_players_map_and_opens_a_session
    make_user
    login_as 'player@example.com', 'a good passphrase'
    assert_equal 200, last_response.status
    assert_equal %w[characters locations users], json.keys.sort
    assert_operator json['locations'].size, :>, 20
    assert_equal 1, json['characters'].size

    header 'Authorization', nil
    get '/user/sight'
    assert_equal 200, last_response.status
    assert_operator json['locations'].size, :>, 20
  end

  def test_login_response_includes_buildings_with_their_type_and_name
    make_user
    login_as 'player@example.com', 'a good passphrase'
    places = json['locations'].flat_map { |l| l['places'] || [] }
    assert_operator places.size, :>, 0
    places.each { |p| assert p['_type']; assert p['name'] }
  end

  def test_every_location_has_coordinates_and_a_terrain_type
    make_user
    login_as 'player@example.com', 'a good passphrase'
    json['locations'].each do |l|
      assert_equal 2, l['c'].size
      assert_includes %w[Plain Forest Hill ForestHill Mountain Lake Sea], l['_type']
    end
  end

  def test_login_accepts_the_email_in_any_case
    make_user
    login_as ' PLAYER@example.COM ', 'a good passphrase'
    assert_equal 200, last_response.status
  end

  def test_signup_then_login_end_to_end
    signup 'e2e@example.com'
    login_as 'e2e@example.com', 'a good passphrase'
    assert_equal 200, last_response.status
    assert_equal 1, json['characters'].size
  end

  def test_sight_requires_a_session
    get '/user/sight'
    assert_equal 401, last_response.status
    assert_equal 'Not logged in.', json['error']
  end

  def test_logout_ends_the_session
    make_user
    login_as 'player@example.com', 'a good passphrase'
    header 'Authorization', nil
    put '/user/logout'
    assert_equal 302, last_response.status
    get '/user/sight'
    assert_equal 401, last_response.status
  end

  # ---- errors --------------------------------------------------------------
  def test_unexpected_errors_return_a_generic_json_message_for_api_routes
    make_user
    User.stub(:authenticate, ->(*) { raise 'secret internals: /path/to/file.rb' }) do
      login_as 'player@example.com', 'a good passphrase'
    end
    assert_equal 500, last_response.status
    assert_equal 'Something went wrong.', json['error']
    refute_includes last_response.body, 'secret internals'
  end

  def test_unexpected_errors_on_pages_render_a_generic_page_without_the_exception
    Sphere.class_eval { get('/__boom') { raise 'private detail' } }
    get '/__boom'
    assert_equal 500, last_response.status
    assert_includes last_response.body, 'Something went wrong'
    refute_includes last_response.body, 'private detail'
    refute_includes last_response.body, '.rb'
  end
end
