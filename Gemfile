source 'https://rubygems.org'
ruby '~> 3.3.14'

gem 'sinatra', '~> 1.4'
gem 'sinatra-contrib', '~> 1.4'
gem 'rack', '< 2.3'
gem 'puma', '~> 5.6'
gem 'haml', '~> 5.2'
gem 'slim'
gem 'coffee-script'
gem 'execjs'
gem 'json', '~> 2.9'
gem 'csv'
gem 'bigdecimal'
gem 'activesupport', '~> 5.2'
gem 'data_mapper', '~> 1.2'
# these two pin the long-dead json 1.x, which does not run on Ruby 3; same code, relaxed gemspec
gem 'dm-types', path: 'patched_gems/dm-types-1.2.2'
gem 'bcrypt'
gem 'dm-serializer', path: 'patched_gems/dm-serializer-1.2.2'
gem 'dm-timestamps'
gem 'dm-validations'

group :production do
  gem 'dm-postgres-adapter'
end

group :development do
  gem 'pry'
  gem 'dm-sqlite-adapter'
end
