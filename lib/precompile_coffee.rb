# Compile the CoffeeScript views to public/js at image build time so the first
# page load doesn't spend ~30s compiling on a small instance. Sinatra serves
# public/ before its routes, so these files take over from the /js/*.js routes.
require 'coffee-script'
%w[script isometric2 components].each do |name|
  js = CoffeeScript.compile(File.read("views/#{name}.coffee"))
  File.write("public/js/#{name}.js", js)
  puts "compiled #{name}.coffee (#{js.bytesize} bytes)"
end
