require 'net/http'
require 'json'

URL = 'https://www.apple.com/de/shop/fulfillment-messages'.freeze # for Germany apple stores

MODEL_CODES = {
  '1' => 'MU793ZD/A' # iPhone 15 Pro Max (Natural Titanium)
}.freeze

ZIPS = {
  '1' => '10210', # Berlin
  '2' => '20110' # Hamburg
}.freeze

def run
  model_code = choose_iphone
  zip        = choose_zip
  response   = make_request(query_params(model_code, zip))

  handle_information_from(response, model_code)
end

def choose_iphone
  puts "Input number of needed iPhone:\n" \
       "1 - iPhone 15 Pro Max 256 Gb (Natural Titanium)\n"
  number = gets.chop
  raise "Invalid number for choosing iPhone! Use only number from #{MODEL_CODES.keys}" if MODEL_CODES[number].nil?

  MODEL_CODES[number]
end

def choose_zip
  puts "Input zip or choose number of zip:\n" \
       "1 - Berlin (10210)\n" \
       "2 - Hamburg (20110)\n"
  zip_or_number = gets.chop

  zip = zip_or_number.length == 5 ? zip_or_number : ZIPS[zip_or_number]
  raise "Invalid zip! Use only zip code with 5 digits or number from #{ZIPS.keys}" if zip.nil?

  zip
end

def query_params(model_code, zip)
  {
	'pl' => true,
	'mts.0' => 'regular',
	'parts.0' => model_code,
	'location' => zip
  }
end

def parse(response)
  raise "Failed response. Status: #{response.code}\nResponse body: #{response.body}" unless response.code == '200'
  JSON.parse(response.body).dig('body')
rescue => e
  puts "Failed response. Status: #{response.code}\nResponse body: #{response.body}"
end

def make_request(query_params)
  uri = URI(URL)
  uri.query = URI.encode_www_form(query_params)

  parse(Net::HTTP.get_response(uri))
end

def handle_information_from(response, model_code)
  available_in_stores = []
  stores = response.dig('content', 'pickupMessage', 'stores')

  stores.each do |store|
    available = store.dig('partsAvailability', model_code, 'pickupDisplay') == 'available'
    available_in_stores << store.dig('storeName') if available
  end

  if available_in_stores == []
  	puts "Unavailable in stores!"
  else
    puts "Available in stores: #{available_in_stores.join(', ')}"
  end
end

run
