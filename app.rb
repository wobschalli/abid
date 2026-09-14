require_relative 'config/environment'

require 'sinatra/activerecord'
require 'phlex-sinatra'
require 'phlex'

class App < Sinatra::Base
  helpers Phlex::Sinatra
  register Sinatra::ActiveRecordExtension

  set :sessions,
      httponly: true,
      secure: production?,
      same_site: :lax,
      expire_after: 60 * 60 * 24 * 14
  set :session_secret, Abid.session_secret

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
    # Case-insensitive: Discord usernames are lowercase now, but rows synced from
    # older accounts can be mixed case.
    user = User.where('lower(username) = ?', params[:username].to_s.strip.downcase).first

    # user may be nil, and authenticate returns false on a bad password, so this
    # has to be a safe-navigation check rather than `user.authenticate(...)`.
    if user&.authenticate(params[:password].to_s)
      session[:user_id] = user.id
      redirect to('/')
    else
      status 401
      phlex Login.new(error: 'Incorrect username or password.')
    end
  end

  get '/logout' do
    session.clear
    redirect to('/login')
  end

  private

  PUBLIC_PATHS = ['/login'].freeze

  def current_user
    return @current_user if defined?(@current_user)
    @current_user = session[:user_id] && User.find_by(id: session[:user_id])
  end

  def leader?
    !!current_user&.leader
  end

  def ensure_logged_in
    return if PUBLIC_PATHS.include?(request.path_info)

    # A stale session cookie pointing at a deleted user (someone left the server)
    # should log out cleanly rather than 500 further down the request.
    return if current_user

    session.clear
    redirect to('/login')
  end

  # Guard for anything that edits data. The bot checks `leader` per command; the
  # web side previously checked only "is logged in".
  def require_leader!
    halt 403, 'Leaders only' unless leader?
  end
end
