require 'sinatra/activerecord'
require 'phlex-sinatra'
require 'phlex'

# In production the secret comes from the SESSION_SECRET env var; locally it
# falls back to the gitignored .session_secret file.
SESSION_SECRET = ENV['SESSION_SECRET'] || begin
  secret_file = File.expand_path('.session_secret', __dir__)
  unless File.exist?(secret_file)
    abort "No session secret: set the SESSION_SECRET env var or create #{secret_file}"
  end
  File.read(secret_file).strip
end

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
