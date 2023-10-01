require 'logger'
require 'net/http'
require 'json'

TELEGRAM_BOT_TOKEN = ''.freeze
TELEGRAM_CHAT_ID = ''.freeze

GERMANY_APPLE_STORE_URL = 'https://www.apple.com/de/shop/fulfillment-messages'.freeze # for Germany Apple Stores

MODEL_CODES = {
  '1' => { code: 'MU793ZD/A', name: 'iPhone 15 Pro Max 256 Gb (Natural Titanium)' },
  '2' => { code: 'MU7A3ZD/A', name: 'iPhone 15 Pro Max 256 Gb (Blue Titanium)' }
}.freeze

ZIPS = {
  '1' => '10210', # Berlin
  '2' => '20110' # Hamburg
}.freeze

def run
  model_info = choose_iphone
  zip        = choose_zip
  response   = fetch_information(model_info, zip)

  handle_information_from(response, model_info)
end

def logger
  @logger ||= Logger.new("#{File.expand_path(File.dirname(__FILE__))}/logs.log", 'weekly', datetime_format: '%Y-%m-%d %H:%M:%S')
end

def choose_iphone
  number = if ARGV[0].nil?
             puts "Input number of needed iPhone:\n" \
                  "1 - iPhone 15 Pro Max 256 Gb (Natural Titanium)\n" \
                  "2 - iPhone 15 Pro Max 256 Gb (Blue Titanium)\n"
             gets.chop
           else
             ARGV[0]
           end

  if MODEL_CODES[number].nil?
    logger.error("Invalid number for choosing iPhone! Use only number from #{MODEL_CODES.keys}")
    raise "Invalid number for choosing iPhone! Use only number from #{MODEL_CODES.keys}"
  end

  MODEL_CODES[number]
end

def choose_zip
  zip_or_number = if ARGV[1].nil?
                    puts "Input zip or choose number of zip:\n" \
                         "1 - Berlin (10210)\n" \
                         "2 - Hamburg (20110)\n"
                    gets.chop
                  else
                    ARGV[1]
                  end
  zip = zip_or_number.length == 5 ? zip_or_number : ZIPS[zip_or_number]

  if zip.nil?
    logger.error("Invalid zip! Use only zip code with 5 digits or number from #{ZIPS.keys}")
    raise "Invalid zip! Use only zip code with 5 digits or number from #{ZIPS.keys}"
  end

  zip
end

def fetch_information(model_info, zip)
  query_params = {
    'pl'       => true,
    'mts.0'    => 'regular',
    'parts.0'  => model_info[:code],
    'location' => zip
  }

  make_request(GERMANY_APPLE_STORE_URL, query_params)
end

def parse(response)
  unless response.code == '200'
    logger.error("Failed response. Status: #{response.code}\nResponse body: #{response.body}")
    raise "Failed response. Status: #{response.code}\nResponse body: #{response.body}"
  end

  logger.debug("Response body: #{response.body}")
  JSON.parse(response.body)
rescue => e
  logger.error("Failed response. Error message: #{e.message}. Status: #{response.code}\nResponse body: #{response.body}")
  raise "Failed response. Error message: #{e.message}. Status: #{response.code}\nResponse body: #{response.body}"
end

def make_request(url, query_params)
  uri = URI(url)
  uri.query = URI.encode_www_form(query_params)

  logger.debug("Request url: #{uri.to_s}")
  parse(Net::HTTP.get_response(uri))
end

def handle_information_from(response, model_info)
  available_in_stores = []
  stores = response.dig('body', 'content', 'pickupMessage', 'stores')

  stores.each do |store|
    available = store.dig('partsAvailability', model_info[:code], 'pickupDisplay') == 'available'
    available_in_stores << store.dig('storeName') if available
  end

  message = "#{model_info[:name]}\n"
  message << (available_in_stores == [] ? "Unavailable in stores!" : "Available in stores: #{available_in_stores.join(', ')}")

  logger.info(message)
  send_message_to_telegram(message) unless available_in_stores == []
  puts message
end

def send_message_to_telegram(message)
  url = "https://api.telegram.org/bot#{TELEGRAM_BOT_TOKEN}/sendMessage"
  query_params = {
    'chat_id' => TELEGRAM_CHAT_ID,
    'text' => message
  }

  response = make_request(url, query_params)
  unless response&.dig('ok') == true
    logger.error("Failed send message to telegram.\nResponse body: #{response}")
    puts "Failed send message to telegram.\nResponse body: #{response}"
  end
end

logger
run
