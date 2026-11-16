require 'test_helper'
require 'coffee-script'

# The browser code is CoffeeScript served by the app (and precompiled at deploy).
class FrontendTest < Minitest::Test
  ROOT = File.expand_path('..', __dir__)

  def test_the_coffeescript_views_compile
    %w[script isometric2].each do |name|
      js = CoffeeScript.compile(File.read("#{ROOT}/views/#{name}.coffee"))
      assert_operator js.size, :>, 1000, name
    end
  end

  def test_the_precompile_script_covers_every_view_the_page_loads
    layout = File.read("#{ROOT}/world.rb")
    loaded = layout.scan(%r{asset\("/js/([\w-]+)\.js"\)}).flatten - %w[underscore-min crafty]
    compiled = File.read("#{ROOT}/lib/precompile_coffee.rb")[/%w\[(.*?)\]/, 1].split
    assert_equal loaded.sort, compiled.sort
    loaded.each { |name| assert File.exist?("#{ROOT}/views/#{name}.coffee"), name }
  end

  def test_every_asset_the_page_links_exists
    File.read("#{ROOT}/world.rb").scan(%r{asset\("(/[^"]+)"\)}).flatten.each do |path|
      next if path =~ %r{/js/(script|isometric2)\.js} # compiled on request or at build time
      assert File.exist?("#{ROOT}/public#{path}"), "public#{path} is missing"
    end
  end

  def test_the_client_reads_the_field_names_the_server_sends
    js = File.read("#{ROOT}/views/script.coffee")
    %w[wood food gold _type].each { |k| assert_includes js, k }
    refute_match(/entity\.r[wgf]\b/, js, 'old short building field names are gone')
  end

  def test_no_third_party_script_hosts_are_referenced
    File.read("#{ROOT}/views/script.coffee").scan(%r{https?://[\w.-]+}).each do |url|
      refute_match(/lovely\.io/, url)
    end
  end

  def test_there_are_no_leftovers_from_the_mongo_era
    code = Dir["#{ROOT}/{models,controllers,lib,tools}/**/*.rb"] + ["#{ROOT}/world.rb", "#{ROOT}/modules.rb", "#{ROOT}/config.ru"]
    code.reject { |f| f.end_with?('frontend_test.rb') }.each do |file|
      text = File.read(file)
      refute_match(/Mongoid|Moped|embeds_many|embedded_in|has_and_belongs_to_many|binding\.pry/, text.gsub(/^\s*#.*$/, ''), file)
    end
    refute File.exist?("#{ROOT}/lib/mongoid_compat.rb")
    refute File.exist?("#{ROOT}/config/mongoid.yml")
  end
end
