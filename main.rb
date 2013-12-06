require 'sinatra'
require 'koala'
require 'kramdown'
require 'data_mapper'
require './secrets'
require 'fileutils'
require 'base64'
require 'pony'

DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/db/development.sqlite3")
# DataMapper::Model.raise_on_save_failure = true
class User
  include DataMapper::Resource
  property :id, Integer, :key => true
  property :username, String
  property :name, String
  property :email, String
  property :created_on, DateTime
  property :updated_at, DateTime
  has n, :comments
  has n, :days
end

class Comment
  include DataMapper::Resource
  property :id, Serial
  property :body, Text
  property :created_on, DateTime
  property :updated_at, DateTime
  belongs_to :user
  belongs_to :day, :required => false
end

class Day
  include DataMapper::Resource
  property :id, Integer, :key => true
  property :title, String
  property :image_url, String
  property :body, Text
  property :publish_on, DateTime  
  property :created_on, DateTime
  property :updated_at, DateTime
  belongs_to :user
  has n, :comments
end

DataMapper.auto_upgrade!

APP_ID = 524306497656258

# your app secret

use Rack::Session::Cookie, :secret => RACK_SECRET

before do

  class Integer
    def to_english
      english_nums = {1=>"one", 2=>"two", 3=>"three", 4=>"four", 5=>"five", 6=>"six", 7=>"seven", 8=>"eight", 9=>"nine", 
        10=>"ten", 11=>"eleven", 12=>"twelve", 13=>"thirteen", 14=>"fourteen", 15=>"fifteen", 16=>"sixteen", 17=>"seventeen", 
        18=>"eighteen", 19=>"nineteen", 20=>"twenty", 21=>"twenty-one", 22=>"twenty-two", 23=>"twenty-three", 24=>"twenty-four"}
      return english_nums[self]
    end
  end

  class String
    def ordinalize
      ns = {"1"=>"st", "2"=>"nd", "3"=>"rd", "4"=>"th", "5"=>"th", "6"=>"th", "7"=>"th", "8"=>"th", "9"=>"th", "10"=>"th", "11"=>"th", 
        "12"=>"th", "13"=>"th", "14"=>"th", "15"=>"th", "16"=>"th", "17"=>"th", "18"=>"th", "19"=>"th", "20"=>"th", "21"=>"st", 
        "22"=>"nd", "23"=>"rd", "24"=>"th", "25"=>"th", "26"=>"th", "27"=>"th", "28"=>"th", "29"=>"th", "30"=>"th", "31"=>"st"} 
      return self + ns[self]
    end
  end

  #helpers
  def logged_in?
    if session['access_token']
      return true
    else
      return false
    end
  end

  def admin?
    if logged_in?
      admins = ADMINS
      if admins.include? @current_user['username']
        return true
      else
        return false
      end
    else
      return false
    end
  end

  def img_tag_for_user(id)
    return "<img src='http://graph.facebook.com/" + id.to_s + "/picture'>"
  end

  if logged_in?
    @current_user = User.get((session['uid'].to_i))
  end

end

get '/' do
  @days = Day.all
  erb :index
end

get '/day/:number/show' do
  @day = Day.get(params['number'])
  @body = Kramdown::Document.new(@day.body).to_html
  @comments = Comment.all(:day => @day)
  erb :show
end

get '/day/:number/edit' do
  if admin?
    day = params['number']
    @day = Day.get(day)
    @body = Kramdown::Document.new(@day.body).to_html
    @file_arr = (Dir.entries("./public/images").sort) - ['.', '..', '.DS_Store']

    erb :edit
  else
    "You have to Log-in with administrative priveledges to do that."
  end
end

post '/day/:number/update' do
  day = Day.first_or_create(:id => params['number'])
  day.title = params[:title]
  day.body = params[:body]
  day.image_url = params[:image_url]
  if @current_user.username != EDITOR
    day.user = @current_user
  end
  day.save
  redirect "/day/#{day.id}/show"
end


post '/image/:size/upload' do
  size = params['size']
  base64 = params['base64']
  img_name = params['imgName']
  # save the array of image data to files
    File.open("public/images/#{size}/#{imgName}", 'wb') do |f|
      f.write(Base64.decode64(base64))
      f.close()

    end
  "success"
end


post '/comment/:num/create' do
  if logged_in?
    day = Day.get(params['num'])
    comment = day.comments.create(:user => @current_user, :body => params[:body])

     Pony.mail({
        :to => day.user.email,
        :subject => comment.user.name + " has left a comment on your post!", 
        :body => "#{comment.user.name} wrote: \n #{comment.body} \n You can go to your post http://advent.cornerstonecity.eu/day/#{comment.day.id}/show to reply or delete the comment if necessary.",
        :via => :smtp,
        :via_options => {
          :address              => ADDRESS,
          :port                 => PORT,
          :enable_starttls_auto => true,
          :user_name            => USER_NAME,
          :password             => PASSWORD,
         :authentication       =>  :plain, # no auth by default
         :domain               => DOMAIN # the HELO domain provided by the client to the server
        }
      })
    redirect '/day/' + day.id.to_s + '/show#createComment'

  else
    "you have to <a href='http://advent.cornerstonecity.eu/login'>log in</a> to leave comments"
  end
end

post '/comment/:id/destroy' do
  if admin?
    comment = Comment.get(params[:id])
    comment.destroy

  else
    "You have to be an admin to delete comments"
  end
end

get '/login' do
  # generate a new oauth object with your app data and your callback url
  session['oauth'] = Koala::Facebook::OAuth.new(APP_ID, APP_SECRET, "#{request.base_url}/callback")
  # redirect to  to get your code
  redirect session['oauth'].url_for_oauth_code()
end

get '/logout' do
  session['oauth'] = nil
  session['access_token'] = nil
  redirect '/'
end

#method to handle the redirect from facebook back to you
get '/callback' do
  #get the access token from facebook with your code
  session['access_token'] = session['oauth'].get_access_token(params[:code])
  graph = Koala::Facebook::API.new(session['access_token'])
  profile = graph.get_object("me")
  session['uid'] = profile['id']

  # if user is not in the database, create the user
  if User.get(profile['id'].to_i) == nil
      puts 'writing to db'
      user = User.create(:id        => profile['id'].to_i, 
                        :username   => profile['username'],
                        :name       => profile['name'],
                        :email      => profile['email'],
                        :created_on => Time.now,
                        :updated_at => Time.now)
  end
  redirect '/'
end