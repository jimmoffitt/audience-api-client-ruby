require 'yaml'
require 'json'
require 'csv'
require 'zlib'
require 'oauth' #OAuth gem is used for non-bearer token OAuth.

require_relative '../common/app_logger'
require_relative '../common/insights_utils'


class AudienceClient

   include AppLogger

   MAX_USERS_PER_SEGMENT_UPLOAD = 100_000
   MIN_USERS_PER_AUDIENCE = 500
   MAX_USERS_PER_AUDIENCE = 30_000_000

   HEADERS = {"content-type" => "application/json"}

   REQUESTS_PER_MINUTE = 12 #Account limits? TODO: default?

   attr_accessor :keys,
				 :api,
				 :base_url, :uri_path, :uri_path_audience, :uri_path_segment,

				 :audience_name,
				 :segment_names, #Usually one name, but can be multiple.
				 :groupings,

				 :account_id,
				 :segment_build_mode,
				 :inbox, #A folder full of Tweet files from Gnip Endpoints.
				 :user_ids, #An array of IDs we are processing.
				 :user_request_groups, #An array of User ID arrays (max of MAX_USERS_PER_SEGMENT_UPLOAD).
				 :outbox, #Where any API outputs are written.
				 :serialize_output,
				 :add_audience_metadata,

				 :utils,
				 :verbose

   def initialize

	  @verbose = false
	  @utils = InsightsUtils.new(@verbose)

	  @user_ids = []
	  @user_request_groups = [] #TODO: doc this... what is this?
	  @@segment_request_num = 1

	  @groupings = []
	  @outbox = './output'
	  @keys = {}
	  
	  @account_id = 0
	  @segment_build_mode = ''

	  @audience_name = 'default_audience'
	  @segment_names = []
	  @segment_names << 'default_segment'

	  @add_audience_metadata = false

	  @base_url = 'https://data-api.twitter.com'
	  @uri_path = '/insights/audience'
	  @uri_path_segment = "#{@uri_path}/segments"
	  @uri_path_audience = "#{@uri_path}/audiences"
   end

   def set_account_config(file)
	  keys = YAML::load_file(file)
	  @keys = keys['audience_api']
   end

   def set_settings_config(file)
	  settings = {}
	  settings = YAML::load_file(file)

	  #Now parse contents and load separate attributes.
	  
	  @account_id = settings['audience_settings']['account_id']
	  @segment_build_mode = settings['audience_settings']['segment_build_mode']

	  @inbox = settings['audience_settings']['inbox'] #Where the Tweets are coming from.
	  @verbose = settings['audience_settings']['verbose']

	  @audience_name = settings['audience_settings']['audience_name']
	  @segment_names = settings['audience_settings']['segment_name']
	  @add_audience_metadata = settings['audience_settings']['add_audience_metadata']

	  @outbox = settings['audience_settings']['outbox']
	  @serialize_output = settings['audience_settings']['serialize_output']
	  @groupings = settings['audience_groupings']

	  #Create folders if they do not exist.
	  if (!File.exist?(@inbox))
		 Dir.mkdir(@inbox)
	  end

	  if (!File.exist?("#{@inbox}/processed"))
		 Dir.mkdir("#{@inbox}/processed")
	  end

	  if (!File.exist?(@outbox))
		 Dir.mkdir(@outbox)
	  end

   end

   # HTTP and OAuth Authentication methods ------------------------------------------------------------------------------
   #TODO: new common class?

   def get_api_access

	  consumer = OAuth::Consumer.new(@keys['consumer_key'], @keys['consumer_secret'], {:site => @base_url})
	  token = {:oauth_token => @keys['access_token'],
			   :oauth_token_secret => @keys['access_token_secret']
	  }

	  @api = OAuth::AccessToken.from_hash(consumer, token)

   end

   def handle_response_error(result)
	  AppLogger.log_error "ERROR. Response code: #{result.code} | Message: #{result.message} | Server says: #{result.body}"
   end

   def make_post_request(uri_path, request)
	  get_api_access if @api.nil? #token timeout?

	  result = @api.post(uri_path, request, HEADERS)

	  if result.code.to_i > 201
		 handle_response_error(result)
	  end

	  result.body
   end

   def make_get_request(uri_path)
	  get_api_access if @api.nil? #token timeout?

	  result = @api.get(uri_path, HEADERS)

	  if result.code.to_i > 201
		 handle_response_error(result)
	  end

	  result.body
   end

   def make_delete_request(uri_path)
	  get_api_access if @api.nil? #token timeout?

	  result = @api.delete(uri_path, HEADERS)


	  if result.code.to_i > 201
		 handle_response_error(result)
	  end

	  result.body
   end

   #Segment methods ----------------------------------------------------------------
   
   
   def get_segments_page(next_parameter)
	  uri_path = "#{@uri_path_segment}#{next_parameter}"
	  response = make_get_request(uri_path)
	  JSON.parse(response)
   end

   def get_segments
	  
	  segments = []
	  
	  no_next_token = false
	  
	  next_parameter = '?next='
	  
	  until no_next_token
		 
		 response = get_segments_page(next_parameter)
		 
		 response['segments'].each do |segment|
			segments << segment
		 end
		 
		 if response['next'].nil?
			no_next_token = true
	     else		
			next_parameter = "?next=#{response['next']}"
			no_next_token = false
		 end
	  end

	  segments_hash = {}
	  segments_hash['segments'] = segments

	  segments_hash
   end

   def get_segment_by_id(id)

	  uri_path = "#{@uri_path_segment}/#{id}"
	  response = make_get_request(uri_path)
	  JSON.parse(response)

   end

   def get_segment_by_name(name)
	  segments = get_segments

	  if segments['errors'].nil?

		 segments['segments'].each { |segment|
			if segment['name'] == name
			   uri_path = "#{@uri_path_segment}/#{segment['id']}"
			   response = make_get_request(uri_path)
			   return JSON.parse(response)
			end
		 }

		 '{"result":"Segment does not exist"}'
	  else 
		 return segments
	  end
   end

   def segment_name_exists?(name)

	  segments = get_segments

	  segments['segments'].each { |segment|
		 if segments['name'] == name
			return true
		 end
	  }

	  false
   end

   def segment_id_exists?(id)

	  segments = []
	  segments = get_segments

	  segments['segments'].each { |segment|
		 if segment['id'] == id
			return true
		 end
	  }

	  false
   end

   def delete_segment_by_id(id)
	  uri_path = "#{@uri_path_segment}/#{id}"
	  response = make_delete_request(uri_path)
	  response
   end

   def delete_segment_by_name(name)

	  #Look up Segments
	  segments = get_segments

	  if segments['errors'].nil?

		 segment_id = ''

		 segments['segments'].each { |segment|

			if segment['name'] == name
			   segment_id = segment['id']
			   break
			end
		 }

		 if not segment_id == ''
			delete_segment_by_id(segment_id)
			AppLogger.log_info "Deleted Segment #{name}..."
		 else
			AppLogger.log_info "Segment #{name} not found. No deletion..."
		 end
	  end

   end

   def delete_all_segments(key = nil)

	  if key.nil?
		 puts "Asking to deleted all segments... are you sure?"
		 return false
	  end

	  segments = {}
	  segments = get_segments
	  segments = JSON.parse(segments)

	  segments['segments'].each { |segment|
		 delete_segment_by_id(segment['id'])
	  }

	  true

   end

   def generate_user_groups_for_segment_requests(user_ids=nil)

	  if user_ids.nil?
		 user_ids = @user_ids
	  end

	  AppLogger.log_info "Have #{user_ids.count} User IDs."
	  AppLogger.log_info "Dividing User list into sets of #{MAX_USERS_PER_SEGMENT_UPLOAD} User IDs." if user_ids.count > MAX_USERS_PER_SEGMENT_UPLOAD

	  #user_ids holds a 'user_ids' array of all users in 'inbox' tweets. Here we split them into MAX_USERS_PER_REQUEST "User IDs" parcels.
	  # ====> loads @user_request_groups[]
	  #@user_request_groups[0] = ['user_id_1', .., 'user_id_100000']
	  #@user_request_groups[1] = ['user_id_100001', .., 'user_id_200000']

	  request_users = [] #Array of up to MAX_USERS_PER_REQUEST.

	  user_ids.each { |user_id|

		 request_users << user_id

		 if request_users.length == MAX_USERS_PER_SEGMENT_UPLOAD
			@user_request_groups << request_users
			request_users = []
		 end
	  }

	  #Handle last batch, not already grabbed in USER_LIMIT chunks above.
	  if request_users.length > 0
		 @user_request_groups << request_users
	  end

	  AppLogger.log_info("Have #{@user_request_groups.length} sets of User IDs groups.") if @user_request_groups.length > 1

	  @user_request_groups

   end

   def create_segment(name)
	  uri_path = @uri_path_segment

	  request = {}
	  request['name'] = name

	  if %w(followed engaged impressed).include? @segment_build_mode.downcase
		 user_ids = []
		 user_ids << @account_id.to_s
		 request[@segment_build_mode] = {}
		 request[@segment_build_mode]['user_ids'] = []
		 request[@segment_build_mode]['user_ids'] = user_ids
	  end
	  
	  if @segment_build_mode.downcase == 'tailored'
		 tailored_audience_ids = []
		 tailored_audience_ids << @account_id.to_s
		 request[@segment_build_mode] = {}
		 request[@segment_build_mode]['tailored_audience_ids'] = []
		 request[@segment_build_mode]['tailored_audience_ids'] = tailored_audience_ids
	  end

	  response = make_post_request(uri_path, request.to_json)

	  #Parse response and return audience_id
	  response = JSON.parse(response)
	  
	  if !response.include?('errors')
	  	AppLogger.log_info "Created #{name} Segment with ID #{response['id']}."
	  end
	  response
   end

   def update_segment(name, user_ids)

	  #First see if Segment exists. If not, create.
	  segment = get_segment_by_name(name)
	  
	  if segment['errors'].nil?
	  
		 if segment['id'].nil?
			segment = create_segment(name)
		 end
		 segment_id = segment['id']
   
		 uri_path = "#{@uri_path_segment}/#{segment_id}/ids"
   
		 #Divide User IDs into multiple groups if needed.
		 @user_request_groups = generate_user_groups_for_segment_requests(user_ids)
   
		 @user_request_groups.each { |user_ids|
			add_users_to_segment(name, segment_id, user_ids)
		 }
   
		 get_segment_by_name(name)
	  else
		 
		 return segment
	  end
		 
   end

   def add_users_to_segment(name, segment_id, user_ids)
	  uri_path = "#{@uri_path_segment}/#{segment_id}/ids"

	  request = {}
	  request['user_ids'] = user_ids

	  response = make_post_request(uri_path, request.to_json)

	  if not response.include? "error"
		 AppLogger.log_info "Added #{user_ids.count} User IDs to #{name}."
	  else
		 AppLogger.log_error "Error response: #{response}."
		 if response.include? "not modifiable"
			AppLogger.log_error "Segment is locked since it has already been included in an Audience."
			AppLogger.log_error "Retry with a new Segment or one not yet included in an Audience."
		 end
	  end

	  response
   end

   def list_segments
	  segments = get_segments

	  if not segments.include?("errors")

		 AppLogger.log_info "Number of Segments: #{segments['segments'].length}"
		 segments['segments'].each { |segment|
			AppLogger.log_info segment
		 }
	  end

   end


   #Audience methods  -------------------------------------------------------------


   def get_audiences_page(next_parameter)
	  uri_path = "#{@uri_path_audience}#{next_parameter}"
	  response = make_get_request(uri_path)
	  JSON.parse(response)
   end
   
   def get_audiences

		 audiences = []

		 no_next_token = false

		 next_parameter = '?next='

		 until no_next_token

			response = get_audiences_page(next_parameter)

			response['audiences'].each do |audience|
			   audiences << audience
			end

			if response['next'].nil?
			   no_next_token = true
			else
			   next_parameter = "?next=#{response['next']}"
			   no_next_token = false
			end
		 end

		 audiences_hash = {}
		 audiences_hash['audiences'] = audiences

		 audiences_hash
   end

   def get_audience_by_id(id)
	  uri_path = "#{@uri_path_audience}/#{id}"
	  response = make_get_request(uri_path)
	  JSON.parse(response)
   end

   def get_audience_by_name(name)

	  audiences = []
	  audiences = get_audiences

	  audiences['audiences'].each { |audience|
		 if audience['name'] == name
			uri_path = "#{@uri_path_audience}/#{audience['id']}"
			response = make_get_request(uri_path)
			return JSON.parse(response)
		 end
	  }

	  '{"result":"Audience does not exist"}'
   end

   def delete_audience_by_id(id)
	  uri_path = "#{@uri_path_audience}/#{id}"
	  response = make_delete_request(uri_path)
	  response
   end

   def delete_audience_by_name(name)

	  audiences = get_audiences


	  if audiences['errors'].nil?
		 audience_id = ''

		 audiences['audiences'].each { |audience|

			if audience['name'] == name
			   audience_id = audience['id']
			   break
			end
		 }

		 if not audience_id == ''
			delete_audience_by_id(audience_id)
		 else
			puts "Audience #{name} not found. No deletion..." if @verbose
		 end
	  end
   end

   def delete_audience_and_its_segments_by_id(audience_id)

	  audience = get_audience_by_id(audience_id)

	  AppLogger.log.info("Deleting these Segments: #{audience['segment_ids']}")

	  audience['segment_ids'].each { |segment_id|
		 delete_segment_by_id(segment_id)
	  }

	  delete_audience_by_id(audience['id'])

   end

   def delete_audience_and_its_segments_by_name(audience_name)

	  audience = get_audience_by_name(audience_name)

	  if audience.include? 'does not exist'
		 AppLogger.log.info("Attempting delete, but Audience #{audience_name} does not exist")
		 return
	  end

	  AppLogger.log.info("Deleting these Segments: #{audience['segment_ids']}")

	  audience['segment_ids'].each { |segment_id|
		 delete_segment_by_id(segment_id)
	  }

	  delete_audience_by_id(audience['id'])

   end

   def audience_name_exists?(name)

	  audiences = []
	  audiences = get_audiences

	  audiences['audiences'].each { |audience|
		 if audience['name'] == name
			return true
		 end
	  }

	  false
   end

   def audience_id_exists?(id)

	  audiences = []
	  audiences = get_audiences

	  audiences['audiences'].each { |audience|
		 if audience['id'] == id
			return true
		 end
	  }

	  false
   end

   def can_create_audience?(segments)

	  num_user_ids = 0

	  segments.each do |segment|
		 num_user_ids += segment['num_user_ids'].to_i
	  end


	  if num_user_ids < MIN_USERS_PER_AUDIENCE
		 AppLogger.log_error "Not enough User IDs to create an Audience. Minimum required is #{MIN_USERS_PER_AUDIENCE}, but only #{num_user_ids} in Segments."
		 return false
	  end

	  if num_user_ids > MAX_USERS_PER_AUDIENCE
		 AppLogger.log_error "Too many User IDs to create an Audience. Maximum allowed is #{MAX_USERS_PER_AUDIENCE}, but #{num_user_ids} in Segments."
		 return false
	  end

	  AppLogger.log_info "Have #{num_user_ids} User IDs in Segments."

	  true

   end

   def create_audience(name, segment_ids)

	  uri_path = @uri_path_audience
	  request = {}
	  request['name'] = name

	  #build Segment ID array
	  request['segment_ids'] = []

	  segment_ids.each { |segment_id|
		 request['segment_ids'] << segment_id
	  }

	  response = make_post_request(uri_path, request.to_json)
	  response = JSON.parse(response)

	  AppLogger.log_info("Created '#{name}' Audience with #{segment_ids.length} Segments. Audience ID: #{response['id']}")
	  AppLogger.log_debug("Request: #{request.to_json}")

	  #TODO: catch errors, like when audience size is too small (or big!)
	 
	  response

   end

   def list_audiences
	  audiences = get_audiences

	  if not audiences.include?("errors")
		 AppLogger.log_info "Number of Audiences: #{audiences['audiences'].length}"
		 audiences['audiences'].each { |audience|
			AppLogger.log_info audience
		 }
	  end
   end

   #Usage methods  -------------------------------------------------------------
   # Usage method
   def get_usage
	  uri_path = '/insights/audience/usage'
	  response = make_get_request(uri_path)
	  JSON.parse(response)
   end


   # Query methods ======================================================================================================

   def query_audience(audience_id, groupings = nil)
	  #   In: Audience UUID, Groupings
	  #   Out: POST /query.json results in JSON.

	  if groupings.nil?
		 groupings = @groupings
	  end

	  uri_path = "#{uri_path_audience}/#{audience_id}/query"

	  request = {}

	  request['groupings'] = {}
	  groupings.each { |key, items|
		 request['groupings'][key] = {}
		 request['groupings'][key]['group_by'] = []
		 items['group_by'].each do |item|
			request['groupings'][key]['group_by'] << item
		 end
	  }

	  response = make_post_request(uri_path, request.to_json)

	  if @add_audience_metadata
		 audience = get_audience_by_id(audience_id)

		 response = JSON.parse(response)

		 response['audience'] = audience

		 #Inject Segment names
		 response['audience']['segment_names'] = []

		 response['audience']['segment_ids'].each { |segment_id|
			segment = get_segment_by_id(segment_id)
			response['audience']['segment_names'] << segment['name']
		 }

		 response = response.to_json
	  end

	  #Write results to outbox.
	  filename = "#{@outbox}/#{@audience_name}_results.json"

	  if @serialize_output
		 num = 1
		 until !File.exists?(filename)
			num += 1
			filename = "#{@outbox}/#{@audience_name}_results_#{num}.json"
		 end
	  end

	  File.open(filename, "w") do |new_file|
		 new_file.write(response)
	  end

	  response

   end

   # -------------------------------------------------------

   def delete_all_audiences_and_segments

	  audiences = get_audiences

	  audiences['audiences'].each { |audience|

		 #Parse Audience ID, and delete its segments.
		 delete_audience_and_its_segments_by_id(audience['id'])

		 #Delete Audience
		 delete_audience_by_id(audience['id'])
	  }
   end

   #Output methods ======================================================================================================

   def print_usage

	  puts
	  puts "Audience usage data:"
	  puts '--------------------'
	  puts get_usage
	  puts

   end

   def print_results(results)
	  #Output API 'query audience' results in a customized way.

	  #Your code here!
	  puts
	  puts "Audience metadata:" if @verbose
	  puts results

	  if @verbose
		 puts '-------------------'
		 puts "Current Segments: #{list_segments}"
		 puts '-------------------'
		 puts "Current Audiences: #{list_audiences}"
	  end
   end

   #=====================================================================================================================
   def files_to_ingest?
	  files_to_ingest = false
	  #Do we have files to process?
	  AppLogger.log_info "Checking inbox for files to process..."
	  files = Dir.glob("#{@inbox}/*.{json, gz}")
	  files += Dir.glob("#{@inbox}/*.{csv}")
	  files_to_ingest = true if files.length > 0
	  files_to_ingest
   end

   def load_ids

	  metadata = {}
	  id_type = 'user_ids'

	  files = Dir.glob("#{@inbox}/*.{json, gz}")
	  if files.length > 0
		 AppLogger.log_info "Found JSON or GZ files to process... Parsing out #{id_type}..."
		 id_types = []
		 id_types << id_type
		 metadata = @utils.load_metadata_from_json(@inbox, id_types, @verbose)
		 metadata["#{id_type}"]
	  end

	  files = Dir.glob("#{@inbox}/*.{csv}")
	  if files.length > 0
		 AppLogger.log_info "Found CSVs... Parsing out #{id_type}..."
		 metadata = @utils.load_metadata_from_csv(@inbox, id_type, @verbose)
	  end

	  #if @save_ids then
	  #	 puts 'Saving Parsed IDs has not been implemented.'
	  #end

	  metadata[id_type]
   end

end

