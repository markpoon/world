require "./lib/app_env"
require "sinatra/base"
require "json"
require "net/http"
require "uri"
require "bigdecimal"
require "set"
require "./modules"
require "data_mapper"

require "./lib/game_model"
require "./models/models.rb"
require "./lib/world_generator"
require "./lib/seed"
require "./controllers/controllers.rb"

module AuthorizationHelpers
  def authorized?; session[:user] ? (return true) : (status 403); end
  def authorize!; redirect '/login' unless authorized?; end  
  def logout!; session[:user] = false; end
end

class Sphere < Sinatra::Base
  enable :inline_templates  
  helpers AuthorizationHelpers

  # Error pages: full stack traces only when SHOW_ERRORS is on (local development
  # by default, never on a public host unless asked); otherwise the generic 500 page.
  set :show_exceptions, AppEnv.show_errors?
  set :dump_errors, true # always log errors to stderr (Render's log viewer)

  # Versioned asset URLs (/css/style.css?v=<mtime>) so browsers, especially
  # iOS Safari, fetch new CSS/JS after a deploy instead of reusing a stale copy.
  helpers do
    def asset(path)
      file = File.join(settings.public_folder, path)
      File.exist?(file) ? "#{path}?v=#{File.mtime(file).to_i}" : path
    end
  end

  configure :development do
    register Sinatra::Reloader if AppEnv.reload_code?

    Bundler.require(:development)
    DataMapper.setup(:default, (ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/dev.db").sub(/\Apostgresql:/, 'postgres:'))
  end

  configure :production do
    Bundler.require(:production)
    DataMapper.setup(:default, (ENV['DATABASE_URL'] || 'postgres://localhost/world').sub(/\Apostgresql:/, 'postgres:'))
  end

  # Debug-only routes (flag ENABLE_DEBUG_ROUTES): a Pry console hook and a route
  # that raises, for checking how errors look in the current mode.
  if AppEnv.debug_routes?
    get '/binding' do
      halt 501, 'Pry is not installed in this mode' unless defined?(Pry)
      Binding.pry
    end
    get '/debug/error' do
      raise 'Deliberate test error from /debug/error'
    end
  end

  DataMapper.finalize.auto_upgrade!
  puts "Cosmic Dream starting: #{AppEnv.summary}"
  Seed.demo_user! if AppEnv.seed_demo_user?

  before "/user/*" do
    content_type 'application/json'
  end

  get "/?" do
    haml :index
  end

  # --- Sign up -------------------------------------------------------------
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  SIGNUP_LIMIT  = 10   # accounts/lookups per network address...
  SIGNUP_WINDOW = 3600 # ...per hour
  SIGNUP_LOG    = {}
  THROTTLE_LOCK = Mutex.new
  CREATE_LOCK   = Mutex.new

  helpers do
    def json_body
      request.body.rewind
      data = JSON.parse(request.body.read.to_s)
      data.is_a?(Hash) ? data : {}
    rescue JSON::ParserError
      nil
    end

    def signup_throttled?
      now = Time.now.to_i
      THROTTLE_LOCK.synchronize do
        recent = (SIGNUP_LOG[request.ip] || []).select { |t| now - t < SIGNUP_WINDOW }
        SIGNUP_LOG[request.ip] = recent
        return true if recent.size >= SIGNUP_LIMIT
        recent << now
        false
      end
    end

    # [lng, lat] from the browser, or the default start area when missing/invalid
    def signup_coordinates(raw)
      lng, lat = Array(raw).first(2).map { |v| Float(v) rescue nil }
      return Seed::CENTER unless lng && lat && lng.between?(-180, 180) && lat.between?(-85, 85)
      [lng, lat]
    end

    def fail_with(code, *messages)
      halt code, { errors: messages }.to_json
    end
  end

  post '/user/signup' do
    data = json_body
    fail_with 400, 'Invalid request.' if data.nil?
    email    = User.normalize_email(data['email'])
    password = data['password'].to_s
    errors = []
    errors << 'Enter a valid email address.' unless email.length <= 254 && email =~ EMAIL_FORMAT
    errors << 'Your passphrase needs at least 8 characters.' if password.length < 8
    errors << 'Your passphrase is too long (128 characters at most).' if password.length > 128
    halt 422, { errors: errors }.to_json unless errors.empty?
    fail_with 429, 'Too many sign-ups from your network. Please try again later.' if signup_throttled?

    lng, lat = signup_coordinates(data['coordinates'])
    World.ensure_area(lng, lat, 6)
    tile = World.tile_at(lng, lat)
    fail_with 500, 'Could not find a starting position. Please try again.' unless tile

    user = nil
    CREATE_LOCK.synchronize do # check + create together, so two requests can't claim one email
      fail_with 422, 'That email is already registered.' if User.first(email: email)
      user = User.new(email: email, password: password)
      user.location = tile
      user.save
    end
    fail_with 500, 'Could not create your account. Please try again.' unless user.saved?
    status 201
    { id: user.id, email: user.email }.to_json
  end

  get '/user/login' do
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    if @auth.provided? and @auth.basic? and @auth.credentials
      email, password = @auth.credentials
      user = User.authenticate(email, password)
      if user
        status 200
        session[:user] = user.id
        u = user.sight
        return u.to_json
      else
        status 401
        return
      end
    else
      status 400
      return
    end
  end

  put '/user/logout' do
    logout!
    @user = nil
    redirect '/'
  end

  get '/user/sight' do
    user = session[:user] && User.get(session[:user])
    halt 401, { error: 'Not logged in.' }.to_json unless user
    user.sight.to_json
  end

  # What mode is the app in? Non-sensitive, so it can be left on in any mode.
  get '/status' do
    content_type 'application/json'
    {
      app: 'cosmic-dream',
      environment: AppEnv.name,
      on_render: AppEnv.on_render?,
      flags: AppEnv.flags,
      ruby: RUBY_VERSION,
      commit: ENV['RENDER_GIT_COMMIT'].to_s[0, 7],
      database: DataMapper.repository.adapter.class.name.split('::').last.sub('Adapter', '').downcase,
      tiles: Location.count,
      buildings: Place.count
    }.to_json
  end

  get '/menus' do
    halt 404 unless params["path"] == "login"
    @options = params["path"].intern
    haml :menu, {:layout => false}
  end

  get "/js/script.js" do
    content_type "text/javascript", :charset => 'utf-8'
    coffee :script
  end
  get "/js/isometric2.js" do
    content_type "text/javascript", :charset => 'utf-8'
    coffee :isometric2
  end

  not_found{haml :'404'}
  # Reached only when show_exceptions is off (see SHOW_ERRORS): never show the
  # exception to visitors; it is already in the server log.
  error do
    if request.path_info.start_with?('/user/')
      content_type 'application/json'
      { error: 'Something went wrong.' }.to_json
    else
      haml :'500'
    end
  end
end

__END__

@@index
#cr-stage

@@layout
!!! 5
%html{lang: "en"}
  %head
    %meta{charset: "utf-8"}
    %title Cosmic Dream
    -# No maximum-scale / user-scalable: pinch-zoom stays available (accessibility).
    -# viewport-fit=cover lets the page use the full screen on notched iPhones.
    %meta{name: "viewport", content: "width=device-width, initial-scale=1, viewport-fit=cover"}
    %meta{name: "color-scheme", content: "dark"}
    %meta{name: "theme-color", content: "#000000"}
    %meta{name: "description", content: "Cosmic Dream: a geolocation-based, turn-based RPG in the browser."}
    %link{href: asset("/css/style.css"), rel: "stylesheet"}
  %body
    = yield
    %noscript
      #noscript This game needs JavaScript. Please enable it and reload the page.
    %script{src: asset("/js/underscore-min.js")}
    %script{src: asset("/js/crafty.js")}
    %script{src: asset("/js/isometric2.js")}
    %script{src: asset("/js/script.js")}

@@menu
#menuContainer
  #menu
    = render 'haml', @options

@@login
-# A real <form>, so the phone keyboard's "Go" key submits it and password
-# managers recognise it. Fields may stay blank: the demo account is used then.
%form#loginForm{action: "#", method: "post", novalidate: true}
  %h1 Cosmic Dream
  %p.hint To try the demo, leave both fields blank and tap Login. To play with your own account, enter an email and a passphrase (8+ characters) and tap Sign Up.
  %label.sr-only{for: "loginEmail"} Email
  %input#loginEmail{type: "email", name: "email", placeholder: "you@example.com", autocomplete: "username", autocapitalize: "none", autocorrect: "off", spellcheck: "false", inputmode: "email", enterkeyhint: "next"}
  %label.sr-only{for: "loginPassword"} Passphrase
  %input#loginPassword{type: "password", name: "password", placeholder: "Passphrase", autocomplete: "current-password", autocapitalize: "none", autocorrect: "off", spellcheck: "false", enterkeyhint: "go"}
  %button#loginButton{type: "submit"} Login
  %button#signupButton{type: "button"} Sign Up
  %p#loginMessage{role: "status", aria: {live: "polite"}}

@@404
.warning
  %h1 404
  %hr 
  Apologies, there were no results found for your query.
  %hr
  
@@500
.warning
  %h1 Something went wrong
  %hr
  %p Sorry, an unexpected error occurred. Please try again in a moment.
  %hr
