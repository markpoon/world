require 'rubygems'
require 'bundler/setup'
require 'sass/plugin/rack'
require 'pry-rescue'
use PryRescue::Rack if ENV["RACK_ENV"] == 'development'
Bundler.require(:default)
use Sass::Plugin::Rack
use Rack::Session::Cookie, key: 'greatly_deserved_deserts', secret: 'the_dream_within_is_also_without', old_secret: 'telltale_signs_of_old_age'

require './world'
run Sphere 
