require "sinatra/base"
require "net/http"
require "uri"
require "bigdecimal"
require "set"
require "./modules"
require "data_mapper"

require "./lib/mongoid_compat"
require "./models/models.rb"
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

  # Versioned asset URLs (/css/style.css?v=<mtime>) so browsers, especially
  # iOS Safari, fetch new CSS/JS after a deploy instead of reusing a stale copy.
  helpers do
    def asset(path)
      file = File.join(settings.public_folder, path)
      File.exist?(file) ? "#{path}?v=#{File.mtime(file).to_i}" : path
    end
  end

  configure :development do
    register Sinatra::Reloader

    Bundler.require(:development)
    DataMapper.setup(:default, (ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/dev.db").sub(/\Apostgresql:/, 'postgres:'))

    # interactive debugger endpoint: never expose it on a public host (Render sets RENDER)
    unless ENV['RENDER']
      get '/binding' do
        Binding.pry
      end
    end
  end

  configure :production do
    Bundler.require(:production)
    DataMapper.setup(:default, (ENV['DATABASE_URL'] || 'postgres://localhost/world').sub(/\Apostgresql:/, 'postgres:'))
  end

  MongoidCompat.finalize!
  DataMapper.finalize.auto_upgrade!
  Seed.demo_user! if ENV['SEED_DEMO_USER'] == '1'

  before "/user/*" do
    content_type 'application/json'
  end

  get "/?" do
    haml :index
  end

  put '/user/new' do
    user = User.where(email: @params[:email]).exists?
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
    user = User.find(session[:user])
    user.sight.to_json
  end

  get '/menus' do
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

  get "/js/components.js" do
    content_type "text/javascript", :charset => 'utf-8'
    coffee :components
  end

  not_found{haml :'404'}
  error{@error = request.env['sinatra_error']; haml :'500'}
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
  %p.hint Demo: leave both fields blank and tap Login.
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
  %h1 500
  %hr
  %p @error.message
  %hr
