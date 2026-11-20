# -*- encoding: utf-8 -*-
# stub: dm-serializer 1.2.2 ruby lib

Gem::Specification.new do |s|
  s.name = "dm-serializer".freeze
  s.version = "1.2.2".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Guy van den Berg".freeze, "Dan Kubb".freeze]
  s.date = "2012-08-02"
  s.description = "DataMapper plugin for serializing Resources and Collections".freeze
  s.email = ["dan.kubb@gmail.com".freeze]
  s.extra_rdoc_files = ["LICENSE".freeze, "README.rdoc".freeze]
  s.files = [".gitignore".freeze, "Gemfile".freeze, "LICENSE".freeze, "README.rdoc".freeze, "Rakefile".freeze, "benchmarks/to_json.rb".freeze, "benchmarks/to_xml.rb".freeze, "dm-serializer.gemspec".freeze, "lib/dm-serializer.rb".freeze, "lib/dm-serializer/common.rb".freeze, "lib/dm-serializer/to_csv.rb".freeze, "lib/dm-serializer/to_json.rb".freeze, "lib/dm-serializer/to_xml.rb".freeze, "lib/dm-serializer/to_yaml.rb".freeze, "lib/dm-serializer/xml.rb".freeze, "lib/dm-serializer/xml/libxml.rb".freeze, "lib/dm-serializer/xml/nokogiri.rb".freeze, "lib/dm-serializer/xml/rexml.rb".freeze, "spec/fixtures/cow.rb".freeze, "spec/fixtures/planet.rb".freeze, "spec/fixtures/quan_tum_cat.rb".freeze, "spec/fixtures/vehicle.rb".freeze, "spec/lib/serialization_method_shared_spec.rb".freeze, "spec/public/serializer_spec.rb".freeze, "spec/public/to_csv_spec.rb".freeze, "spec/public/to_json_spec.rb".freeze, "spec/public/to_xml_spec.rb".freeze, "spec/public/to_yaml_spec.rb".freeze, "spec/rcov.opts".freeze, "spec/spec.opts".freeze, "spec/spec_helper.rb".freeze, "tasks/spec.rake".freeze, "tasks/yard.rake".freeze, "tasks/yardstick.rake".freeze]
  s.homepage = "http://datamapper.org".freeze
  s.rubygems_version = "1.8.15".freeze
  s.summary = "DataMapper plugin for serializing Resources and Collections".freeze

  s.specification_version = 3

  s.add_runtime_dependency(%q<fastercsv>.freeze, ["~> 1.5".freeze])
  s.add_runtime_dependency(%q<multi_json>.freeze, ["~> 1.0".freeze])
  s.add_runtime_dependency(%q<json>.freeze, [">= 1.6".freeze])
  s.add_runtime_dependency(%q<dm-core>.freeze, ["~> 1.2.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 0.9".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 1.3".freeze])
end

