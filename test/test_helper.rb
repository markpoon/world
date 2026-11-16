# Shared setup for the test suite. Run everything with:
#
#   bundle exec ruby test/all.rb
#
# or one file with:  bundle exec ruby -Itest test/api_test.rb
#
# The app is loaded exactly as config.ru loads it, against a throwaway SQLite
# file, with the debug/reload flags forced off (like a public deploy).
require 'tmpdir'
require 'fileutils'

ENV['RACK_ENV']             = 'development'
ENV['RELOAD_CODE']          = 'false'
ENV['ENABLE_DEBUG_ROUTES']  = 'false'
ENV['SHOW_ERRORS']          = 'false'
ENV['SEED_DEMO_USER']       = 'false'
ENV['LOAD_OVERTURE']        = 'false' # tests load their own small POI files
ENV['SESSION_SECRET']       = 'test-secret-test-secret-test-secret-test-secret-0123456789'
TEST_DB_DIR = Dir.mktmpdir('world-test')
# Set TEST_DATABASE_URL (e.g. postgres://user:pw@host/db) to run the suite on Postgres.
ENV['DATABASE_URL'] = ENV['TEST_DATABASE_URL'] || "sqlite3://#{TEST_DB_DIR}/test.db"
at_exit { FileUtils.rm_rf(TEST_DB_DIR) }

Dir.chdir(File.expand_path('..', __dir__)) # config.ru uses ./relative requires
$stdout_orig = $stdout
quiet = File.open(File::NULL, 'w')
$stdout = quiet # the app prints a startup banner
$stderr_orig = $stderr
$stderr = quiet # ...and noisy gem deprecation warnings
require 'rack/test'
APP, _opts = Rack::Builder.parse_file('config.ru')
$stdout = $stdout_orig
$stderr = $stderr_orig

Sinatra::Application.set :run, false if defined?(Sinatra::Application) # no auto-started server
Sphere.set :dump_errors, false                                         # keep test output clean
require 'minitest/autorun'

# Base class: an empty database for every test.
class WorldTest < Minitest::Test
  def setup
    adapter = DataMapper.repository.adapter
    tables = DataMapper::Model.descendants.map { |m| m.storage_name }.uniq
    tables += join_tables
    quoted = tables.map { |t| adapter.send(:quote_name, t) }
    if adapter.class.name =~ /Postgres/
      adapter.execute("TRUNCATE #{quoted.join(', ')} RESTART IDENTITY CASCADE")
    else
      quoted.each { |t| adapter.execute("DELETE FROM #{t}") }
    end
    Sphere::SIGNUP_LOG.clear
  end

  # Temporarily change environment variables inside the block.
  def with_env(vars)
    saved = vars.keys.map { |k| [k, ENV[k]] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  # The many-to-many join tables DataMapper generated.
  def join_tables
    @@join_tables ||= DataMapper::Model.descendants.flat_map { |m| m.relationships.map { |r| r.respond_to?(:through) && r.through.respond_to?(:target_model) ? r.through.target_model.storage_name : nil } }.compact.uniq - DataMapper::Model.descendants.map(&:storage_name)
  end

  # Run a block, hiding what it prints (journeys narrate their stories, users announce themselves).
  def quietly
    result = nil
    capture_io { result = yield }
    result
  end

  def new_journey(attrs = {}); quietly { Journey.create(attrs) }; end

  # A start tile (and its surroundings) to attach users to.
  def start_tile
    World.ensure_area(*Seed::CENTER, 6)
    World.tile_at(*Seed::CENTER)
  end

  def make_user(email = 'player@example.com', password = 'a good passphrase')
    user = User.new(email: email, password: password)
    user.location = start_tile
    capture_io { user.save } # the app prints a "has joined the game" line
    user
  end
end
