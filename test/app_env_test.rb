require 'test_helper'

# AppEnv decides which optional features (debug routes, stack traces, code
# reloading, demo seeding) are on. The rule: on locally in development, never on
# a public host (Render) unless explicitly asked for.
class AppEnvTest < WorldTest
  CLEAN = { 'RACK_ENV' => nil, 'RENDER' => nil, 'ENABLE_DEBUG_ROUTES' => nil, 'SHOW_ERRORS' => nil,
            'RELOAD_CODE' => nil, 'SEED_DEMO_USER' => nil }.freeze

  def env(overrides = {}, &block); with_env(CLEAN.merge(overrides), &block); end

  def test_defaults_to_development
    env { assert_equal 'development', AppEnv.name; assert AppEnv.development?; refute AppEnv.production? }
  end

  def test_production_mode
    env('RACK_ENV' => 'production') { assert AppEnv.production?; refute AppEnv.development? }
  end

  def test_local_development_turns_the_dev_helpers_on
    env do
      assert AppEnv.local_dev?
      assert AppEnv.debug_routes?
      assert AppEnv.show_errors?
      assert AppEnv.reload_code?
    end
  end

  def test_seed_demo_user_is_off_unless_asked_for
    env { refute AppEnv.seed_demo_user? }
    env('SEED_DEMO_USER' => '1') { assert AppEnv.seed_demo_user? }
  end

  def test_development_on_a_public_host_keeps_the_helpers_off
    env('RENDER' => 'true') do
      assert AppEnv.development?
      assert AppEnv.on_render?
      refute AppEnv.local_dev?
      refute AppEnv.debug_routes?
      refute AppEnv.show_errors?
      refute AppEnv.reload_code?
    end
  end

  def test_a_flag_can_be_forced_on_even_on_a_public_host
    env('RENDER' => 'true', 'SHOW_ERRORS' => 'true') { assert AppEnv.show_errors? }
  end

  def test_a_flag_can_be_forced_off_locally
    env('ENABLE_DEBUG_ROUTES' => 'false') { refute AppEnv.debug_routes? }
  end

  def test_production_defaults_the_helpers_off
    env('RACK_ENV' => 'production') { refute AppEnv.debug_routes?; refute AppEnv.show_errors?; refute AppEnv.reload_code? }
  end

  def test_flag_parsing_accepts_the_usual_truthy_words
    %w[1 true TRUE yes On].each { |v| env('SEED_DEMO_USER' => v) { assert AppEnv.seed_demo_user?, v } }
  end

  def test_flag_parsing_treats_everything_else_as_off
    %w[0 false no off nope 2].each { |v| env('SEED_DEMO_USER' => v) { refute AppEnv.seed_demo_user?, v } }
  end

  def test_blank_flag_falls_back_to_the_default
    env('SHOW_ERRORS' => '  ') { assert AppEnv.show_errors? } # local dev default
  end

  def test_flags_hash_and_summary
    env('RENDER' => 'true') do
      assert_equal %i[debug_routes show_errors reload_code seed_demo_user load_overture], AppEnv.flags.keys
      assert_match(/env=development on_render=true/, AppEnv.summary)
      assert_match(/debug_routes=false/, AppEnv.summary)
    end
  end
end
