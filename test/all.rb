# Runs the whole suite:  bundle exec ruby test/all.rb
$LOAD_PATH.unshift(File.expand_path(__dir__))
Dir.glob(File.expand_path('*_test.rb', __dir__)).sort.each { |f| require f }
