# -*- encoding: utf-8 -*-
# stub: dm-types 1.2.2 ruby lib

Gem::Specification.new do |s|
  s.name = "dm-types".freeze
  s.version = "1.2.2".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Dan Kubb".freeze]
  s.date = "2012-08-02"
  s.description = "DataMapper plugin providing extra data types".freeze
  s.email = ["dan.kubb@gmail.com".freeze]
  s.extra_rdoc_files = ["LICENSE".freeze, "README.rdoc".freeze]
  s.files = [".gitignore".freeze, "Gemfile".freeze, "LICENSE".freeze, "README.rdoc".freeze, "Rakefile".freeze, "dm-types.gemspec".freeze, "lib/dm-types.rb".freeze, "lib/dm-types/api_key.rb".freeze, "lib/dm-types/bcrypt_hash.rb".freeze, "lib/dm-types/comma_separated_list.rb".freeze, "lib/dm-types/csv.rb".freeze, "lib/dm-types/enum.rb".freeze, "lib/dm-types/epoch_time.rb".freeze, "lib/dm-types/file_path.rb".freeze, "lib/dm-types/flag.rb".freeze, "lib/dm-types/ip_address.rb".freeze, "lib/dm-types/json.rb".freeze, "lib/dm-types/paranoid/base.rb".freeze, "lib/dm-types/paranoid_boolean.rb".freeze, "lib/dm-types/paranoid_datetime.rb".freeze, "lib/dm-types/regexp.rb".freeze, "lib/dm-types/slug.rb".freeze, "lib/dm-types/support/dirty_minder.rb".freeze, "lib/dm-types/support/flags.rb".freeze, "lib/dm-types/uri.rb".freeze, "lib/dm-types/uuid.rb".freeze, "lib/dm-types/yaml.rb".freeze, "spec/fixtures/api_user.rb".freeze, "spec/fixtures/article.rb".freeze, "spec/fixtures/bookmark.rb".freeze, "spec/fixtures/invention.rb".freeze, "spec/fixtures/network_node.rb".freeze, "spec/fixtures/person.rb".freeze, "spec/fixtures/software_package.rb".freeze, "spec/fixtures/ticket.rb".freeze, "spec/fixtures/tshirt.rb".freeze, "spec/integration/api_key_spec.rb".freeze, "spec/integration/bcrypt_hash_spec.rb".freeze, "spec/integration/comma_separated_list_spec.rb".freeze, "spec/integration/dirty_minder_spec.rb".freeze, "spec/integration/enum_spec.rb".freeze, "spec/integration/epoch_time_spec.rb".freeze, "spec/integration/file_path_spec.rb".freeze, "spec/integration/flag_spec.rb".freeze, "spec/integration/ip_address_spec.rb".freeze, "spec/integration/json_spec.rb".freeze, "spec/integration/slug_spec.rb".freeze, "spec/integration/uri_spec.rb".freeze, "spec/integration/uuid_spec.rb".freeze, "spec/integration/yaml_spec.rb".freeze, "spec/rcov.opts".freeze, "spec/shared/flags_shared_spec.rb".freeze, "spec/shared/identity_function_group.rb".freeze, "spec/spec.opts".freeze, "spec/spec_helper.rb".freeze, "spec/unit/bcrypt_hash_spec.rb".freeze, "spec/unit/csv_spec.rb".freeze, "spec/unit/enum_spec.rb".freeze, "spec/unit/epoch_time_spec.rb".freeze, "spec/unit/file_path_spec.rb".freeze, "spec/unit/flag_spec.rb".freeze, "spec/unit/ip_address_spec.rb".freeze, "spec/unit/json_spec.rb".freeze, "spec/unit/paranoid_boolean_spec.rb".freeze, "spec/unit/paranoid_datetime_spec.rb".freeze, "spec/unit/regexp_spec.rb".freeze, "spec/unit/uri_spec.rb".freeze, "spec/unit/uuid_spec.rb".freeze, "spec/unit/yaml_spec.rb".freeze, "tasks/spec.rake".freeze, "tasks/yard.rake".freeze, "tasks/yardstick.rake".freeze]
  s.homepage = "http://datamapper.org".freeze
  s.rubygems_version = "1.8.15".freeze
  s.summary = "DataMapper plugin providing extra data types".freeze

  s.specification_version = 3

  s.add_runtime_dependency(%q<bcrypt-ruby>.freeze, ["~> 3.0".freeze])
  s.add_runtime_dependency(%q<fastercsv>.freeze, ["~> 1.5".freeze])
  s.add_runtime_dependency(%q<multi_json>.freeze, ["~> 1.0".freeze])
  s.add_runtime_dependency(%q<json>.freeze, [">= 1.6".freeze])
  s.add_runtime_dependency(%q<stringex>.freeze, ["~> 1.4".freeze])
  s.add_runtime_dependency(%q<uuidtools>.freeze, ["~> 2.1".freeze])
  s.add_runtime_dependency(%q<dm-core>.freeze, ["~> 1.2.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 0.9".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 1.3".freeze])
end

