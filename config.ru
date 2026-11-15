require 'rubygems'
require 'bundler/setup'
require 'sass/plugin/rack'
Bundler.require(:default, ENV['RACK_ENV'] == 'production' ? :production : :development)
use Sass::Plugin::Rack
use Rack::Session::Cookie, key: 'greatly_deserved_deserts',
  secret: ENV.fetch('SESSION_SECRET', 'dev-only-secret-change-me-dev-only-secret-change-me-0123456789')

require './world'
run Sphere
