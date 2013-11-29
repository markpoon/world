require "sinatra/base"
require "net/http"
require "uri"
require "bigdecimal"
require "set"
require "modules"
require "data_mapper"

require "./models/models.rb"
require "./controllers/controllers.rb"

module AuthorizationHelpers
  def authorized?; session[:user] ? (return true) : (status 403); end
  def authorize!; redirect '/login' unless authorized?; end  
  def logout!; session[:user] = false; end
end

class Sphere < Sinatra::Base
  enable :inline_templates  
  helpers AuthorizationHelpers

  configure :development do
    register Sinatra::Reloader

    Bundler.require(:development)
    DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/dev.db")

    get '/binding' do
      Binding.pry
    end
  end

  configure :production do
    Bundler.require(:production)
    DataMapper.setup(:default, 'postgres://localhost/world')
  end

  DataMapper.finalize.auto_upgrade!

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
%html
  %head
    %title Cosmic - Geolocation game written in coffeescript, lovely.io, crafty.js, backend in ruby, sinatra, mongodb
    %meta{name: "viewport", content: "width=device-width,user-scalable=0,initial-scale=1.0,minimum-scale=0.5,maximum-scale=1.0"}
    %link{href: "css/style.css", rel: "stylesheet"}
  %body
    = yield
  %footer
  %script{src: "http://cdn.lovely.io/core.js", type: "text/javascript"}
  %script{src: "/js/underscore-min.js", type: "text/javascript"}  
  %script{src: "/js/crafty.js", type: "text/javascript"}
  %script{src: "/js/isometric2.js", type: "text/javascript"}
  %script{src: "/js/script.js", type: "text/javascript"}

@@menu
#menuContainer
  #menu
    = render 'haml', @options

@@login
Demo: no email or password
%input{:type => "text", :id =>"loginEmail", :name => "email", :placeholder => "Your@Email.com"}
%input{:type => "text", :id =>"loginPassword", :name => "password", :placeholder => "Pass Phrase"}
%button{:id =>"loginButton"} Login
%button{:id =>"loginButton"} Sign Up
  
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
