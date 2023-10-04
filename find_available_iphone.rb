require 'logger'
require 'net/http'
require 'json'

DEBUG_LOGS_ENABLED = false.freeze

TELEGRAM_BOT_TOKEN = ''.freeze
TELEGRAM_CHAT_ID = ''.freeze

APPLE_STORE_URL = 'https://www.apple.com/de/shop/fulfillment-messages'.freeze # for Germany Apple Stores

MODEL_CODES = {
  '1' => { code: 'MU793ZD/A', name: 'iPhone 15 Pro Max 256 Gb (Natural Titanium)' },
  '2' => { code: 'MU7A3ZD/A', name: 'iPhone 15 Pro Max 256 Gb (Blue Titanium)' }
}.freeze

ZIPS = {
  '1' => '10210', # Berlin
  '2' => '20110', # Hamburg
  '3' => '19376' # Between Berlin and Hamburg
}.freeze

def run
  models_info = choose_iphones
  zip         = choose_zip
  response    = fetch_information(models_info, zip)

  handled_infos = handle_information_from(response, models_info)
  print_and_send_messages(handled_infos)
end

def logger
  @logger ||= Logger.new("#{File.expand_path(File.dirname(__FILE__))}/logs.log",
                         'weekly',
                         datetime_format: '%Y-%m-%d %H:%M:%S',
                         progname: 'find_available_iphone',
                         level: DEBUG_LOGS_ENABLED ? Logger::DEBUG : Logger::INFO)
end

def choose_iphones
  models_info = []
  numbers = if ARGV[0].nil? || ARGV[0] == '' || ARGV[0] == ' '
             puts "Input number or numbers of needed iPhone (example, '1 2 3' or 1):\n" \
                  "1 - iPhone 15 Pro Max 256 Gb (Natural Titanium)\n" \
                  "2 - iPhone 15 Pro Max 256 Gb (Blue Titanium)\n"
             gets.chop.strip.split(' ')
           else
             ARGV[0].strip.split(' ')
           end

  numbers.each do |number|
    if MODEL_CODES[number].nil?
      logger.error("Invalid number for choosing iPhone! Use only number from #{MODEL_CODES.keys}")
      raise "Invalid number for choosing iPhone! Use only number from #{MODEL_CODES.keys}"
    end

    models_info << MODEL_CODES[number].merge(stores: [], present: false)
  end

  models_info
end

def choose_zip
  zip_or_number = if ARGV[1].nil? || ARGV[1] == '' || ARGV[1] == ' '
                    puts "Input zip or choose number of zip:\n" \
                         "1 - Berlin (10210)\n" \
                         "2 - Hamburg (20110)\n" \
                         "3 - Between Berlin and Hamburg (19376)\n"
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

def fetch_information(models_info, zip)
  query_params = {
    'pl'       => true,
    'mts.0'    => 'regular',
    'location' => zip
  }.tap do |p|
    models_info.each_with_index {|model_info, i| p["parts.#{i}"] = model_info[:code]}
  end

  make_request(APPLE_STORE_URL, query_params)
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

def handle_information_from(response, models_info)
  unless (error_message = response.dig('body', 'content', 'pickupMessage', 'errorMessage')).nil?
    logger.error("Error message present: #{error_message}")
    raise "Error message present: #{error_message}"
  end

  response.dig('body', 'content', 'pickupMessage', 'stores').each do |store|
    models_info.each_with_index do |model_info, i|
      if store.dig('partsAvailability', model_info[:code], 'pickupDisplay') == 'available'
        models_info[i][:present] = true
        models_info[i][:stores] << "#{store.dig('city')}: #{store.dig('storeName')}"
      end
    end
  end

  models_info
end

def print_and_send_messages(handled_infos)
  message_with_all_information = ''
  message_with_available_iphones = ''

  handled_infos.each do |handled_info|
    if handled_info[:present] == true
      message = "[AVAILABLE IN STORES]\n#{handled_info[:name]}\n#{handled_info[:stores].join(', ')}.\n\n"
      message_with_available_iphones << message
      message_with_all_information << message
    else
      message_with_all_information << "[UNAVAILABLE IN STORES]\n#{handled_info[:name]}\n\n"
    end
  end

  logger.info(message_with_all_information.chop.chop)
  send_message_to_telegram(message_with_available_iphones) unless message_with_available_iphones == ''
  puts message_with_all_information.chop
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
