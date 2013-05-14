require 'rubygems'
require 'bundler'
require 'sass/plugin/rack'
require 'sidekiq'

Bundler.require

use Sass::Plugin::Rack
use Rack::Session::Cookie, key: 'greatly_deserved_deserts', secret: 'the_dream_within_is_also_without', old_secret: 'telltale_signs_of_old_age'

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add Kiqstand::Middleware
  end
end

require './app'
run App