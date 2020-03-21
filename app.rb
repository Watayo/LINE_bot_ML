require 'bundler/setup'
Bundler.require
require 'sinatra/reloader' if development?
require 'json'
require 'jwt'
require 'line/bot'

require 'google/apis/calendar_v3'
require 'googleauth'

require 'fileutils'
require 'json'

enable :sessions
Dotenv.load #.envファイルを読み込む必須

get '/' do
  "Hello, Worlds!"
end

# -------------Google calender-------------
class Calender
  def initialize
    @service = Google::Apis::CalenderV3::CalenderService.new
    @service.client_options.application_name = ENV['APPLICATION_NAME']
    @service.authorization = authorization
    @calender_id = ENV['MY_CALENDER_ID']
  end

  def authorize
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(ENV['CLIENT_SECRET_PATH']),
      scope: Google::Apis::CalenderV3::AUTH_CALENDER
    )
    authorizer.fetch_access_token!
    authorizer
  end

  def get_schedule(time_min = Time.now.iso8601, time_max = (Time.now + 24*60*60*7*0).iso8601, max_results = 256)
    response = @service.list_events(@calendar_id,
                                    max_results: max_results,
                                    single_events: true,
                                    order_by: 'startTime',
                                    time_min: Time.now.iso8601)
    response.items
  end
end

# ------------LINE botの設定----------------
def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_id = ENV["LINE_CHANNEL_ID"]
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)
  events.each do |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        message = {
          type: 'text',
          text: event.message['text']
        }
        client.reply_message(event['replyToken'], message)
      when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
        response = client.get_message_content(event.message['id'])
        tf = Tempfile.open("content")
        tf.write(response.body)
      end
    end
  end

  # Don't forget to return a successful response
  "OK"
end