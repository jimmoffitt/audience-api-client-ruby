=begin
Manages configuration files, command-line options and application session logic. 
Examples of these work sessions include:
+ Building Segments from collections of User IDs.
+ Having a collection of User IDs, building a Segment and an Audience, and querying that Audience.
+ Adding a new Segment to and existing Audience.

Creates one instance of the AudienceClient (audience_client.rb) class.
Mixing in/includes AppLogger Module.

Start here if you are adding/changing command-line details.
No API requests are made directly from app.

=end

def have_name?(name)
   if name == 'none' or name == 'nil' or name.nil? or name == ''
	  return false
   end
   true
end

def multiple_segments?(name)
   if name.include?(',')
	  return true
   end
   false
end

#=======================================================================================================================
if __FILE__ == $0 #This script code is executed when running this file.

   require 'optparse'
   require 'fileutils'

   require_relative './common/app_logger'
   require_relative './lib/audience_client'

   #include AppLogger

   #-------------------------------------------------------------------------------------------------------------------
   #Example command-lines

   #Options:


   #Pass in two files, the account and app settings configuration files.
   # $ruby ./audience_app.rb -a "./config/account.yaml" -c "./config/app_settings.yaml"

   OptionParser.new do |o|

	  #Passing in a config file.... Or you can set a bunch of parameters.
	  o.on('-a ACCOUNT', '--account', 'Account configuration file (including path) that provides API keys for access.') { |account| $account = account }
	  o.on('-c CONFIG', '--config', 'Settings configuration file (including path) that provides app settings.') { |config| $settings = config }
	  o.on('-n AUDIENCE_NAME', '--audience_name', "The name of the 'target' Audience being created/updated/queried.") { |audience_name| $audience_name = audience_name }
	  o.on('-s SEGMENT_NAME', '--segment_name', "The name of the 'target' Segment being created/updated and added to the 'target' Audience.") { |segment_name| $segment_name = segment_name }
	  
	  o.on('-p path', '--path', 'Path and filename to a data file to process.') { |path| $path = path }

	  o.on('-m', '--manage', 'Manage Segments and Audience.') { |manage| $manage = manage }
	  o.on('-l', '--list', 'List all defined Audiences and Segments.') { |list| $list = list }
	  o.on('-u', '--usage', 'Get usage data for your Audience API product.') { |usage| $usage = usage }
	  o.on('-d', '--delete', 'DELETE configured Audience and Segment.') { |delete| $delete = delete }
	  o.on('-f', '--force', 'DELETE ALL Audiences and Segments.') { |force| $force = force }
	  o.on('-v', '--verbose', 'When verbose, output all kinds of things... ') { |verbose| $verbose = verbose }

	  #Help screen.
	  o.on('-h', '--help', 'Display this screen.') do
		 puts o
		 exit
	  end

	  o.parse!

   end

   #If not passed in, use some defaults.
   if ($account.nil?) then
	  $account = "./config/accounts.yaml"
   end

   if ($settings.nil?) then
	  $settings = './config/app_settings.yaml'
   end

   # -------------------------------------------------------------------

   Client = AudienceClient.new()
   Client.set_account_config($account)
   Client.set_settings_config($settings)
   Client.verbose = true if !$verbose.nil?

   AppLogger.config_file = $settings
   AppLogger.set_config(Client.verbose)
   AppLogger.log_path = File.expand_path(AppLogger.log_path)
   AppLogger.set_logger

   #Set-up access token.
   Client.get_api_access

   #Set application attributes from command-line. These override values in the configuration file.
   if !$audience_name.nil?
	  if $audience_name == "" or $audience_name == "nil"
		 $audience_name == "none"
	  end
	  Client.audience_name = $audience_name
   end

   if !$segment_name.nil?
	  if $segment_name == "" or $segment_name == "nil"
		 $audience_name == "none"
	  end
	  Client.segment_names = $segment_name
   end

   segment_names = []
   if multiple_segments?(Client.segment_names)
	  segment_names = Client.segment_names.split(',')
	  segment_names = segment_names.map do |name|
		 name.strip
	  end
   else 
	  segment_names << Client.segment_names.strip
   end

   #---------------------------------------------------------------------------------------
   #Four fundamental modes supported by this simple app:
   # 1) List objects.
   if $list
	  Client.list_segments
	  Client.list_audiences
	  exit
   end

   # 2) Get Usage.
   if $usage
	  Client.print_usage
	  exit
   end

   have_segment_name = have_name?(Client.segment_names)
   have_audience_name = have_name?(Client.audience_name)

   #3) Delete objects.
   if $delete and not $force

	  if have_segment_name
		 segment_names.each do |segment_name|
			Client.delete_segment_by_name(segment_name)
		 end
		 
		 #AppLogger.log_info "Deleted Segment #{Client.segment_name}."
		 Client.list_segments if Client.verbose
	  end

	  if have_audience_name
		 Client.delete_audience_by_name(Client.audience_name)
		 #AppLogger.log_info "Deleting Audience #{Client.audience_name}."
		 Client.list_audiences if Client.verbose
	  end

	  exit
   end

   #There are also other more ambitious delete methods you can force.
   #if $delete and $force
   #  AppLogger.log_info "Deleting all Audiences #{Client.audience_name} and their Segments."
   #  Client.delete_all_audiences_and_segments
   #  exit
   #end

   if $manage or $manage.nil? #So, manage is the default, so nil is a trigger to manage too...

	  #4) Build/manage/query Audience/Segment objects.

	  #---------------------------------------------------------------------------------------------------------------------
#Segment Requests and Management.
	  AppLogger.log_info("Starting build process at #{Time.now}")
	  AppLogger.log_info("Starting Segment management...") if have_segment_name

	  files_to_ingest = Client.files_to_ingest? #Are there files to process?
	  continue = true

	  if files_to_ingest

		 Client.user_ids = Client.load_ids

		 if have_segment_name
			#With multiple segment names, only the first one created/updated....
			AppLogger.log_info "Creating or updating Segment #{segment_names[0]} and adding User IDs..."
			segment = Client.update_segment(segment_names[0], Client.user_ids)
			if not segment['errors'].nil?
			   AppLogger.log_error "ERROR: Creating or updating Segment failed with error #{segment['error']}. Quitting."
			   continue = false
			end
		 else
			AppLogger.log_error "ERROR. Have User IDs to add, but no Segment name provided. Quitting."
			continue = false
		 end
	  else
		 AppLogger.log_info "No new User IDs to process..."
	  end	 

	  if continue and have_segment_name and have_audience_name

		 AppLogger.log_info "Retrieving Segment(s): #{Client.segment_names}"
		 segments = []
		 
		 segment_names.each do |segment_name|
			segment = Client.get_segment_by_name(segment_name)

			if segment.include? "does not exist"
			   AppLogger.log_warn "Specified Segment #{segment_name} does not exist... Skipping it..."
			else
				segments << segment
			end
		 end
	  end

	  #Audience Requests and Management.

	  #Retrieve or Build Audience.
	  if continue and have_audience_name
		 AppLogger.log_info("Starting Audience management...") 
		 
		 audience = Client.get_audience_by_name(Client.audience_name)

		 if audience['id'].nil?
			AppLogger.log_warn "Audience #{Client.audience_name} does not exist... "
			
			if segments.count == 0 
			   AppLogger.log_error "Attempting to create Audience #{Client.audience_name} but no Segments to build Audience with, quitting."
			   continue = false
			else

			   continue = Client.can_create_audience?(segments)
			   
			   unless continue == false
				  segment_ids = []
				  
				  segments.each do |segment|
					 segment_ids << segment['id']
				  end

				  audience = Client.create_audience(Client.audience_name, segment_ids)

				  if not audience['errors'].nil?
					 AppLogger.log_error "Error occurred creating Audience: #{audience}"
					 continue = false
				  end
			   end
			end
		 end
	  end

	  #Add Segment to Audience?
	  if continue and have_audience_name
		 if not segments.nil?
			#If Audience does not refer to this Segment, add Segment to Audience
			
			segments.each do |segment|
			   segment_in_audience = false


			   audience['segment_ids'].each do |existing_segment_id|
				  if existing_segment_id == segment['id']
					 segment_in_audience = true
				  end
			   end

			   if not segment_in_audience #append Segment to Audience's array of Segments.
				  #Audiences only have create and delete methods, there is no update.
				  #Steps: clone audience, update segment array, delete original, create new with clone
				  AppLogger.log_info "Adding Segment to Audience."
				  audience_update = audience
				  audience_update['segment_ids'] << segment['id']
				  Client.delete_audience_by_name(Client.audience_name)
				  Client.create_audience(Client.audience_name, audience_update['segment_ids'])
				  audience = Client.get_audience_by_name(Client.audience_name)
			   end
			end
		 else
			AppLogger.log_error "No Segments to add to Audience."
		 end
	  else
		 AppLogger.log_info "No Audience to query, no more work to do..."
		 continue = false
	  end

	  #Query Audience
	  if continue
		 AppLogger.log_info "Querying Audience..."
		 Client.print_results(Client.query_audience(audience['id'])) unless Client.groupings.nil?
	  end

	  #------------------------------------------------------------------
	  AppLogger.log_info("Finished at #{Time.now}")
   end
end


=begin

   Audience Client App
   1) Builds single Audience based on set of tweets obtained with any Gnip endpoint.
																		   2) Applies configured "groupings" to Audience and returns JSON results.

																																			  Two config files:
																																							 accounts.yaml : OAuth keys and tokens.
	   app_settings.yaml : Audience and Segment names, Audience groupings.

																1a) Parses HPT and Search output and extracts User IDs.
																												   1b) Adds Users to one or more Segments (max. of 100K Users).
	   1c) Builds one Audience based Segments.

									 2) Once Audience is built, requires a single request, applying configured 'groupings.'

#To-do:
# [] Error handling
#   [] Request for configured audience fails? OAuth fail?
#   [] Any request with non-200.
# [] Logging:
#    log.debug: all requests/responses.
#    log.error: all non-200 responses.

# [] Separate Build and Ask concerns. Build once, Ask many, many times.

   ----------------
   Use-patterns for this app:

# [] If User IDs are being passed in, build one Segment based on them.
# [] If building a Segment, add it to the specified Audience.
# [] If Audience does not exist, create it and add Segment if created.
# [] If no Segment is created, just retrieve Audience.
# [] Apply Groupings to Audience.

# [] Adding a new Segment to an existing Audience?
# [] Just apply Groupings? No new User IDs provided, thus no new Segment, retrieve Audience, query, quit.
# [] Adding new User IDs to an existing Segment?
# [] Reloading, where the specified Segment is deleted first, and rebuilt.
# [] Any time a Segment is deleted, the specified Audience is checked to see if it references the deleted Segment.

				   If Audience does not exist, create it too,
														 adding New Segment.
# [] If Audience name does not exist, buildexists, if not build it with one Segment.
# [] If i
# [] Option to delete one Audience.
# [] Option to delete all Segments.


																		* Takes a collection of Tweets, builds a single Segment and adds it to a selected Audience, and queries it with a set of
				   Groupings..

				   * Queries that Audience on an ad hoc basis.

															------------
				   Helper methods.

					   * Delete Audience by name.
												* Delete all Segments associated with an Audience.

																							 Command-line examples:
					   audience_app.rb -c -a -l #Just list my Segments and Audiences.
				   audience_app.rb -c -a  #Load User IDs, create/retrieve Segment, add Users to Segment, add Segment to Audience if needed, query Audience with Groupings.
				   audience_app.rb -c -a -d #Delete configured Audience and Segment.

=end
  
  
  
  
  
  
  
  
  
  
  
  
