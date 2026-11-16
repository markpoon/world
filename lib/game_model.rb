# The persistence layer of the game: plain DataMapper on Postgres (production)
# or SQLite (development and tests).
#
# Every model does `include GameModel` instead of `include DataMapper::Resource`.
# It adds what all of them share and nothing else:
#
#   * id (serial), type (single-table inheritance discriminator), created_at
#   * `symbol` and `list`/`dict` property helpers (see below)
#   * `after_build { ... }` - code that runs when a record is first built in Ruby
#   * `inc(:field, n)`, `_type`
#   * `serialize(*names)` - the explicit JSON each model sends to the browser
#
# Relationships are ordinary DataMapper: has n / belongs_to, and many-to-many
# through real join tables (`has n, :journeys, through: Resource`).
require 'data_mapper'
require 'dm-types'
require 'dm-validations'
require 'dm-timestamps'
require 'dm-migrations'
require 'active_support'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/object/json'

# dm-types 1.2.2 tries to extend nil/frozen values on modern Rubies
require 'dm-types/support/dirty_minder'
module DataMapper::Property::DirtyMinder
  private
  def hook_value(resource, value)
    return if value.nil? || value.frozen? || value.kind_of?(Hooker)
    value.extend Hooker
    value.track(resource, self)
  end
end

Boolean = DataMapper::Property::Boolean unless defined?(Boolean)

# A Ruby Symbol stored in a text column (:female, :departure, :wood ...).
class DataMapper::Property::SymbolText < DataMapper::Property::String
  length 255
  def load(value);  value.nil? ? nil : value.to_s.to_sym; end
  def dump(value);  value.nil? ? nil : value.to_s; end
  def typecast_to_primitive(value); value.nil? ? nil : value.to_s; end
  def primitive?(value); value.nil? || value.is_a?(::Symbol) || value.is_a?(::String); end
  def valid?(value, negated = false); true; end
  def get(resource); value = super; value.nil? ? nil : value.to_sym; end
end

module GameModel
  def self.included(model)
    model.send(:include, DataMapper::Resource)
    model.send(:include, Instance) # after Resource, so these methods win
    model.extend ClassMethods
    model.property :id, DataMapper::Property::Serial
    model.property :type, DataMapper::Property::Discriminator
    model.property :created_at, DataMapper::Property::DateTime
  end

  module ClassMethods
    # property :name, Symbol-like text column
    def symbol(name, **opts)
      opts = opts.merge(required: false)
      default = opts.delete(:default)
      opts[:default] = default.respond_to?(:call) ? proc { |_r, _p| default.call } : default unless default.nil?
      property name, DataMapper::Property::SymbolText, **opts
    end

    # property :name, JSON array / hash column with a fresh default each time
    def list(name, default: [])
      property name, DataMapper::Property::Json, required: false,
               default: proc { |_r, _p| default.respond_to?(:call) ? default.call : default.dup }
    end

    def dict(name, default: {})
      list(name, default: default)
    end

    # Code to run when a record is first built in Ruby (not when loaded from the
    # database). Runs for the class and its ancestors, oldest first.
    def after_build(&block)
      (@build_hooks ||= []) << block
    end

    def build_hooks; @build_hooks || []; end

    # Every class below this one in the inheritance tree (not the class itself).
    def descendant_classes; descendants.to_a - [self]; end

    # The record at exactly these coordinates, if any (Location and Sector).
    def at(coordinates)
      first(cx: coordinates[0].to_f, cy: coordinates[1].to_f)
    end
  end

  module Instance
    def initialize(*args, &block)
      super
      self.class.ancestors.reverse.each do |klass|
        next unless klass.respond_to?(:build_hooks)
        klass.build_hooks.each { |hook| instance_exec(&hook) }
      end
    end

    def _type; self.class.name; end

    # Atomically-ish add to a numeric column.
    def inc(field, amount = 1)
      update(field => (public_send(field) || 0) + amount)
    end

    # The JSON sent to the browser: the named properties/methods, without blanks.
    #   serialize :id, :name, items: :items   # `items` is rendered with each item's own JSON
    def serialize(*names, **renamed)
      json = {}
      names.each { |n| json[n.to_s] = public_send(n) }
      renamed.each { |key, source| json[key.to_s] = public_send(source) }
      json.each_with_object({}) do |(key, value), out|
        next if value.nil? || (value.is_a?(Array) && value.empty?)
        out[key] = value.respond_to?(:as_json) ? value.as_json : value
      end
    end

    def as_json(*)
      serialize(:id)
    end
  end
end
