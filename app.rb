require 'sinatra/activerecord'
require 'phlex-sinatra'
require 'phlex'

SESSION_SECRET = File.read('.session_secret')

class App < Sinatra::Base
  helpers Phlex::Sinatra
  register Sinatra::ActiveRecordExtension

  enable :sessions
  set :session_secret, SESSION_SECRET

  before do
    ensure_logged_in
  end

  get '/' do
    phlex Home.new
  end

  get '/login' do
    phlex Login.new
  end

  post '/login' do
    user = User.find_by(username: params[:username])
    if user.authenticate(params[:password])
      session[:user_id] = user.id
      redirect to('/')
    else
      phlex Login.new
    end
  end

  get '/logout' do
    session[:user_id] = nil
    redirect to('/login')
  end

  private
  def ensure_logged_in
    redirect to('/login') unless session[:user_id] || request.path_info == '/login'
  end
end
