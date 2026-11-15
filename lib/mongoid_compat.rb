# Lets the original Mongoid-style model declarations (field, embedded_in,
# has_and_belongs_to_many, after_initialize ...) run on DataMapper, so the game
# can be stored in Postgres (Render) or SQLite (development).
require 'data_mapper'
require 'dm-types'
require 'dm-serializer'
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
module Moped; module BSON; ObjectId = Integer; end; end
module Mongoid
  module Timestamps
    module Created
      def self.included(base); end
    end
  end
end

module MongoidCompat
  # relationships that must be wired once every model class exists
  PENDING = []

  def self.finalize!
    PENDING.each do |kind, owner, name, child|
      case kind
      when :embedded_in
        owner.belongs_to name, class_name: name.to_s.camelize unless owner.relationships.named?(name)
      when :embeds
        child_model = Object.const_get(child)
        parent_key = owner.name.underscore.to_sym
        child_model.belongs_to parent_key, class_name: owner.name unless child_model.relationships.named?(parent_key)
        owner.has Infinity, name, child, child_key: [:"#{parent_key}_id"] unless owner.relationships.named?(name)
      end
    end
    PENDING.clear
  end

  module InstanceMethods
    def initialize(*args, &block)
      super
      self.class.ancestors.reverse.each do |k|
        next unless k.instance_variable_defined?(:@_after_initialize)
        k.instance_variable_get(:@_after_initialize).each { |b| instance_exec(&b) }
      end
    end
    def _id; id; end
    def persisted?; saved?; end
    def new_record?; new?; end
    def inc(field, amount = 1)
      update(field => (send(field) || 0) + amount)
    end
    def as_json(options = {})
      options = options.dup
      options[:only] = Array(options[:only]).map { |k| k == :_id ? :id : k }
      super(options)
    end
  end

  module ClassMethods
    TYPES = {
      String => String, Integer => Integer, Boolean => Boolean,
      Symbol => String, Float => Float,
      Array => DataMapper::Property::Json, Hash => DataMapper::Property::Json
    }

    def field(short, opts = {})
      name = (opts[:as] || short).to_s
      bool = name.end_with?('?')
      name = name.chomp('?').to_sym
      type = opts[:type] || String
      sym = (type == Symbol)
      default = opts[:default]
      dm_opts = { required: false }
      if default.respond_to?(:call)
        dm_opts[:default] = proc { |_r, _p| default.call }
      elsif !default.nil?
        dm_opts[:default] = default.is_a?(Array) || default.is_a?(Hash) ? proc { |_r, _p| default.dup } : default
      end
      dm_opts[:length] = 255 if TYPES[type] == String
      property name, TYPES.fetch(type), **dm_opts
      if sym
        define_method(name) { v = super(); v && v.to_sym }
      end
      alias_method :"#{name}?", name if bool
      short = short.to_sym
      if short != name && !method_defined?(short)
        define_method(short) { v = attribute_get(name); sym && v ? v.to_sym : v }
        define_method(:"#{short}=") { |v| attribute_set(name, v) }
      end
    end

    def belongs_to_compat(name, opts = {}); end

    def embedded_in(name, opts = {})
      return if opts[:polymorphic]
      MongoidCompat::PENDING << [:embedded_in, self, name, nil]
    end

    def embeds_many(name, opts = {})
      child = (opts[:class_name] || name.to_s.singularize.camelize)
      MongoidCompat::PENDING << [:embeds, self, name, child]
    end

    def has_many(name, opts = {})
      klass = opts[:class_name] || name.to_s.singularize.camelize
      inverse = opts[:inverse_of] || self.name.underscore
      has Infinity, name, klass, child_key: [:"#{inverse}_id"]
    end

    def has_one(name, opts = {}); end

    def belongs_to(name, opts = {})
      klass = opts[:class_name] || name.to_s.camelize
      super(name, klass, required: false)
    end

    # many-to-many stored as an array of ids on this side
    def has_and_belongs_to_many(name, opts = {})
      klass = opts[:class_name] || name.to_s.singularize.camelize
      ids = :"#{name.to_s.singularize}_ids"
      property ids, DataMapper::Property::Json, required: false, default: proc { |_r, _p| [] }
      define_method(name) do
        list = send(ids) || []
        list.empty? ? [] : Object.const_get(klass).all(id: list).to_a
      end
      define_method("#{name}=") { |records| send("#{ids}=", Array(records).map(&:id)) }
    end

    %w[validates_presence_of validates_uniqueness_of validates_length_of
       validates_associated validates_numericality_of validate].each do |m|
      define_method(m) { |*a| }
    end

    def index(*); end

    def after_initialize(&b); (@_after_initialize ||= []) << b; end
    def before_save(&b);   before(:save, &b);   end
    def after_save(&b);    after(:save, &b);    end
    def before_create(&b); before(:create, &b); end
    def around_create(&b); before(:create, &b); end
    def after_create(&b);  after(:create, &b);  end
    def after_update(&b);  after(:update, &b);  end

    def find(id); get(id); end
    def find_by(conds); first(compat_conditions(conds)); end
    def where(conds = {}); all(compat_conditions(conds)); end
    def subclasses; descendants.to_a - [self]; end
    def create!(*a); create(*a); end

    # Mongoid's 2d geo query -> bounding box + distance filter
    def within_circle(conds)
      center, radius = conds[:coordinates]
      all(:cx.gte => center[0] - radius, :cx.lte => center[0] + radius,
          :cy.gte => center[1] - radius, :cy.lte => center[1] + radius)
        .select { |l| Math.hypot(l.cx - center[0], l.cy - center[1]) <= radius }
        .tap { |hits| return all(:id => hits.map(&:id)) }
    end

    def compat_conditions(conds)
      conds = conds.dup
      if (c = conds.delete(:coordinates))
        conds[:cx], conds[:cy] = c.map(&:to_f)
      end
      conds
    end
  end
end

class DataMapper::Collection
  def exists?; !empty?; end
  def without(*); self; end
end

module MongoidCompatRoot
  def included(model)
    super
    model.send(:include, MongoidCompat::InstanceMethods) unless model.ancestors.include?(MongoidCompat::InstanceMethods)
    model.extend MongoidCompat::ClassMethods
    model.property :id, DataMapper::Property::Serial
    model.property :type, DataMapper::Property::Discriminator
    model.property :created_at, DataMapper::Property::DateTime
  end
end
DataMapper::Resource.singleton_class.prepend(MongoidCompatRoot)
