require 'rubygems'
require 'bundler/setup'
require 'sass/plugin/rack'
require './lib/app_env'
# the Postgres adapter lives in :production; load it in development too so a
# DATABASE_URL pointing at Postgres works there
Bundler.require(:default, AppEnv.production? ? :production : :development, :production)
use Sass::Plugin::Rack
use Rack::Session::Cookie, key: 'greatly_deserved_deserts',
  secret: ENV.fetch('SESSION_SECRET', 'dev-only-secret-change-me-dev-only-secret-change-me-0123456789')

require './world'
run Sphere
