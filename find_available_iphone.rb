require 'net/http'
require 'json'

URL = 'https://www.apple.com/de/shop/fulfillment-messages'.freeze # for Germany apple stores

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
  response   = make_request(query_params(model_info, zip))

  handle_information_from(response, model_info)
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

  raise "Invalid number for choosing iPhone! Use only number from #{MODEL_CODES.keys}" if MODEL_CODES[number].nil?

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
  raise "Invalid zip! Use only zip code with 5 digits or number from #{ZIPS.keys}" if zip.nil?

  zip
end

def query_params(model_info, zip)
  {
	  'pl' => true,
	  'mts.0' => 'regular',
	  'parts.0' => model_info[:code],
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

def handle_information_from(response, model_info)
  available_in_stores = []
  stores = response.dig('content', 'pickupMessage', 'stores')

  stores.each do |store|
    available = store.dig('partsAvailability', model_info[:code], 'pickupDisplay') == 'available'
    available_in_stores << store.dig('storeName') if available
  end

  puts model_info[:name]
  if available_in_stores == []
  	puts "Unavailable in stores!"
  else
    puts "Available in stores: #{available_in_stores.join(', ')}"
  end
end

run
