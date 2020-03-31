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

# -------------Google calender-------------

APPLICATION_NAME = 'line-calender-bot'
MY_CALENDAR_ID = 'ryo0616mani@gmail.com'
CLIENT_SECRET_PATH = 'json/line-bot-1584786230158-490e708234e3.json'

class Calendar
  def initialize
    @service = Google::Apis::CalendarV3::CalendarService.new
    @service.client_options.application_name = APPLICATION_NAME
    @service.authorization = authorize
    @calendar_id = MY_CALENDAR_ID
  end

  def authorize
    authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: File.open(CLIENT_SECRET_PATH),
      scope: Google::Apis::CalendarV3::AUTH_CALENDAR
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




# ------------ROUTING設定----------------
get '/' do

  google = Calendar.new
  plans = google.get_schedule
  texts = []
  plans.each do |plan|
    texts.push plan.summary + "\r" #summary = カレンダー情報の題名

  end


  "Hello, Worlds!"
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


  google = Calendar.new
  plans = google.get_schedule

  events = client.parse_events_from(body)
  events.each do |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        if event.message['text'] =~ /スケジュール/
          google = Calendar.new
          plans = google.get_schedule
            if !plans.nil?
              message = {
                type: 'text',
                text: "あなたの今後1週間の予定は\r"
              }
              num = 0
              plans.each do |plan|
                num += 1
                message[:text] = message[:text] << "#{num} : #{plan.summary}\r"
              end
              message[:text] << "..頑張ってね（´ω｀）ﾄﾎﾎ…"
              client.reply_message(event['replyToken'], message)
            else
              message = {
                type: 'text',
                text: "あなたの今後1週間の予定はありません！٩( ᐛ )و"
              }
              client.reply_message(event['replyToken'], message)
            end
        end

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