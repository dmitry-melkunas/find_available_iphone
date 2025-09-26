require 'logger'
require 'net/http'
require 'json'

DEBUG_LOGS_ENABLED = false
USE_INPUT_COOKIE = false

TELEGRAM_BOT_TOKEN = ''.freeze
TELEGRAM_CHAT_ID = ''.freeze

APPLE_COOKIE_URL = 'https://www.apple.com/shop/address/cookie'.freeze
APPLE_COOKIE_VERIFICATION_URL = 'https://www.apple.com/shop/shld/work/v1/q?wd=0'.freeze

USER_AGENT = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'.freeze
COOKIE = nil

AVAILABLE_COUNTRIES = {
  '1' => 'usa',
  '2' => 'germany'
}.freeze

SETTINGS = {
  'usa' => {
    apple_store_url: 'https://www.apple.com/shop/fulfillment-messages',
    currency: 'USD',
    model_codes: {
      '1' => { code: 'MFXG4LL/A', price: 1199, name: 'iPhone 17 Pro Max 256 Gb (Silver)' },
      '2' => { code: 'MFXH4LL/A', price: 1199, name: 'iPhone 17 Pro Max 256 Gb (Cosmic Orange)' },
      '3' => { code: 'MFXJ4LL/A', price: 1199, name: 'iPhone 17 Pro Max 256 Gb (Deep Blue)' }
    },
    zip_codes: {
      '1' => { code: '10010', city: 'New York', state: 'NY', tax: 8.88 },
      '2' => { code: '19720', city: 'New Castle', state: 'DE', tax: 0.0 }
    }
  },
  'germany' => {
    apple_store_url: 'https://www.apple.com/de/shop/fulfillment-messages',
    currency: 'EUR',
    model_codes: {
      '1' => { code: 'MFYM4ZD/A', price: 1449, name: 'iPhone 17 Pro Max 256 Gb (Silver)' },
      '2' => { code: 'MFYN4ZD/A', price: 1449, name: 'iPhone 17 Pro Max 256 Gb (Cosmic Orange)' },
      '3' => { code: 'MFYP4ZD/A', price: 1449, name: 'iPhone 17 Pro Max 256 Gb (Deep Blue)' }
    },
    zip_codes: {
      '1' => { code: '10210', city: 'Berlin' },
      '2' => { code: '20110', city: 'Hamburg' },
      '3' => { code: '19367', city: 'Between Berlin and Hamburg' }
    }
  }
}.freeze

def logger
  @logger ||= Logger.new("#{File.expand_path(File.dirname(__FILE__))}/logs.log",
                         'weekly',
                         datetime_format: '%Y-%m-%d %H:%M:%S',
                         progname: 'find_available_iphone',
                         level: DEBUG_LOGS_ENABLED ? Logger::DEBUG : Logger::INFO)
end

def run
  country     = choose_country
  models_info = choose_phones(country)
  zip         = choose_zip(country)
  cookie      = fetch_cookies
  information = fetch_information(cookie, country, models_info, zip)

  handled_infos = handle_information_from(information, models_info)
  print_and_send_messages(country, handled_infos)
end

def choose_country
  input_value = ARGV[0]

  available_countries = AVAILABLE_COUNTRIES.map do |index, country|
    "#{index} - #{country}"
  end.join("\n")

  country_or_number = if [nil, '', ' '].include?(input_value)
                        puts "Input country in downcase or choose number of country:\n" \
                             "#{available_countries}\n"

                        gets.chop
                      else
                        input_value
                      end

  country = country_or_number.length >= 3 ? country_or_number : AVAILABLE_COUNTRIES[country_or_number]

  if country.nil? || !AVAILABLE_COUNTRIES.values.include?(country)
    error_message = "Invalid country! Use only country names (#{AVAILABLE_COUNTRIES.values.join(', ')}) in downcase or numbers (#{AVAILABLE_COUNTRIES.keys.join(', ')})"
    logger.error(error_message)
    raise error_message
  end

  country
end

def choose_phones(country)
  input_value = ARGV[1]

  available_phones = SETTINGS.dig(country, :model_codes).map do |index, phone_info|
    "#{index} - #{phone_info[:name]}"
  end.join("\n")

  models_info = []
  numbers = if [nil, '', ' '].include?(input_value)
              puts "Input number or numbers of needed iPhone (example, '1 2 3' or 1):\n" \
                   "#{available_phones}\n"

              gets.chop.strip.split(' ')
            else
              input_value.strip.split(' ')
            end

  numbers.each do |number|
    if SETTINGS.dig(country, :model_codes, number).nil?
      error_message = "Invalid number for choosing iPhone! Use only numbers (#{SETTINGS.dig(country, :model_codes).keys.join(', ')})"
      logger.error(error_message)
      raise error_message
    end

    models_info << SETTINGS.dig(country, :model_codes, number).merge(stores: [], present: false)
  end

  models_info
end

def choose_zip(country)
  input_value = ARGV[2]

  available_zips = SETTINGS.dig(country, :zip_codes).map do |index, zip_info|
    "#{index} - #{[zip_info[:city], zip_info[:state]].compact.join(', ')} (#{zip_info[:code]})"
  end.join("\n")

  zip_or_number = if [nil, '', ' '].include?(input_value)
                    puts "Input zip or choose number of zip:\n" \
                         "#{available_zips}\n"

                    gets.chop
                  else
                    input_value
                  end

  zip = zip_or_number.length == 5 ? zip_or_number : SETTINGS.dig(country, :zip_codes, zip_or_number)

  if zip.nil?
    error_message = "Invalid zip! Use only zip code with 5 digits or numbers (#{SETTINGS.dig(country, :zip_codes).keys.join(', ')})"
    logger.error(error_message)
    raise error_message
  end

  zip
end

def fetch_cookies
  return COOKIE if USE_INPUT_COOKIE

  sleep(1)
  initial_cookies_response = make_request('get', APPLE_COOKIE_URL, nil, nil)
  initial_cookies = parse(initial_cookies_response, cookies: true)
  initial_cookie = build_cookie(initial_cookies)

  sleep(1)
  get_verification_task_response = make_request('get', APPLE_COOKIE_VERIFICATION_URL, nil, initial_cookie)
  get_verification_task = parse(get_verification_task_response)

  verification_result_params = build_verification_params(get_verification_task)

  sleep(0.1)
  confirm_verification_task_response = make_request('post', APPLE_COOKIE_VERIFICATION_URL, verification_result_params, initial_cookie)
  verification_cookies = parse(confirm_verification_task_response, cookies: true)
  verification_cookie = build_cookie(verification_cookies)

  [initial_cookie, verification_cookie].join('; ')
end

def fetch_information(cookie, country, models_info, zip)
  query_params = {
    'pl'       => true,
    'mts.0'    => 'regular',
    'location' => zip[:code]
  }.tap do |p|
    models_info.each_with_index { |model_info, i| p["parts.#{i}"] = model_info[:code] }
    p['cppart'] = 'UNLOCKED/US' if country == 'usa'
  end

  response = make_request('get', SETTINGS.dig(country, :apple_store_url), query_params, cookie)
  parse(response)
end

def parse(response, cookies: false)
  unless response.code == '200'
    error_message = "Failed response. Status: #{response.code}"
    send_message_to_telegram(error_message)

    detailed_error_message = "#{error_message}\nResponse body: #{response.body}"
    logger.error(detailed_error_message)
    raise detailed_error_message
  end

  logger.debug("Response body: #{response.body}")
  return parse_cookies(response) if cookies

  JSON.parse(response.body)
rescue => e
  error_message = "Failed response. Error message: #{e.message}. Status: #{response.code}"
  send_message_to_telegram(error_message)

  detailed_error_message = "#{error_message}\nResponse body: #{response.body}"
  logger.error(detailed_error_message)
  raise detailed_error_message
end

def parse_cookies(response)
  cookies = response&.get_fields('Set-Cookie')
  return cookies unless cookies.nil?

  error_message = 'Failed to fetch cookies from response'
  logger.error(error_message)
  raise error_message
end

def build_cookie(cookies)
  return cookies.map { |cookie| cookie.split(';').first }.join('; ') unless [nil, []].include?(cookies)

  error_message = 'Failed to get cookies in array'
  logger.error(error_message)
  raise error_message
end

def make_request(method, url, params, cookie)
  method = method.to_s.downcase
  http_class = case method
               when 'get'  then Net::HTTP::Get
               when 'post' then Net::HTTP::Post
               end

  uri = URI(url)
  uri.query = URI.encode_www_form(params) if method == 'get' && !params.nil?

  logger.debug("#{method.upcase} request to url: #{uri}\nBody: #{params&.to_json}")

  request = http_class.new(uri)
  request['Accept'] = 'application/json'
  request['Content-Type'] = 'application/json' if method == 'post'
  request['User-Agent'] = USER_AGENT
  request['Cookie'] = cookie if cookie

  Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(request) }
end

def build_verification_params(params)
  if params.nil? || params == {}
    error_message = 'Failed to get verification task params'
    logger.error(error_message)
    raise error_message
  end

  {
    'X' => params['X'],
    'result' => params['result'],
    'low' => params['low'],
    'timeout' => params['timeout'],
    'signature' => params['signature'],
    'high' => params['high'],
    'parts' => params['parts'],
    't' => params['t'],
    'flagskv' => {
      'patSkip' => true
    },
    'number' => calculate_numbers_for_verification_task(params['result'], params['low'], params['high'], params['parts']),
    'took' => 1
  }
end

def calculate_numbers_for_verification_task(result, low, high, parts)
  result = result.to_i
  low = low.to_i
  high = high.to_i
  parts = parts.to_i

  backtrack = lambda do |current, product|
    if current.length == parts
      return current if product == result

      return
    end

    (low..high).each do |i|
      next unless (result % (product * i)).zero?

      next_solution = backtrack.call(current + [i], product * i)
      return next_solution if next_solution
    end

    nil
  end

  backtrack.call([], 1)
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
        models_info[i][:stores] << { city: store['city'], state: store['state'], name: store['storeName'] }.compact
      end
    end
  end

  models_info
end

def print_and_send_messages(country, handled_infos)
  message_with_all_information = ''
  message_with_available_phones = ''

  handled_infos.each do |handled_info|
    if handled_info[:present] == true
      message = "[AVAILABLE IN #{country.upcase} STORES]\n" \
        "#{handled_info[:name]}\n" \
        "STORES:\n" \
        "#{build_available_stores_result(country, handled_info)}.\n\n"

      message_with_available_phones << message
      message_with_all_information << message
    else
      message_with_all_information << "[UNAVAILABLE IN #{country.upcase} STORES]\n#{handled_info[:name]}\n\n"
    end
  end

  logger.info(message_with_all_information.chop.chop)
  send_message_to_telegram(message_with_available_phones) unless message_with_available_phones == ''
  puts message_with_all_information.chop
end

def build_available_stores_result(country, info)
  info[:stores].map do |store|
    "#{store[:city]}#{store[:state].nil? ? '' : ", #{store[:state]}"} (#{store[:name]}): #{calculate_phone_price(info[:price], country, store)}"
  end.join("\n")
end

def calculate_phone_price(price, country, store)
  return price.to_s if store[:state].nil? || fetch_tax_percent(country, store[:state]).nil?

  tax_percent = fetch_tax_percent(country, store[:state])
  (price + (price * tax_percent / 100)).round(2).to_s
end

def fetch_tax_percent(country, state)
  @fetch_tax_percent ||= SETTINGS.dig(country, :zip_code).values.find { |zip_info| zip_info[:state] == state }&.dig(:tax)
end

def send_message_to_telegram(message)
  url = "https://api.telegram.org/bot#{TELEGRAM_BOT_TOKEN}/sendMessage"
  query_params = {
    'chat_id' => TELEGRAM_CHAT_ID,
    'text' => message
  }

  response = make_request('get', url, query_params, nil)
  return if response&.dig('ok') == true

  error_message = "Failed send message to telegram.\nResponse body: #{response}"
  logger.error(error_message)
  puts error_message
end

logger
run
