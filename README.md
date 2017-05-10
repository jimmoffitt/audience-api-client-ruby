# audience-api-client-ruby
## An example Audience API client written in Ruby. 

## Note: legacy code kept around as example code for future Twitter Insights APIs.
## No longer available @TwitterDev github.

+ [Introduction](#introduction)
  + [Overview](#overview)
  + [User-story](#user-story)
  + [Managing Segments and Audiences](#managing-segments-and-audiences)
  + [Example Usage Patterns](#example-usage-patterns)
+ [Getting Started](#getting-started)
  + [Configuring Client](#configuring-client) 
    + [Account Configuration](#account-configuration) 
    + [App Setting Configuration](#app-settings-configuration) 
    + [Audience Groupings](#audience-groupings) 
    + [Logging](#logging) 
    + [Command-line Options](#command-line-options)
+ [Client Output](#client-output)
+ [Other Details](#other-details)
  + [Ingesting User IDs](#ingesting-user-ids)
+ [Digging into the client code](#digging-into-the-code)
  + [audience_app.rb](#audience_app)
  + [lib/audience_client.rb](#audience_client)
  + [common/insights_utils.rb](#insights_utils)
  + [common/app_logger.rb](#app_logger)

## Introduction <a id="introduction" class="tall">&nbsp;</a>

### Overview <a id="overview" class="tall">&nbsp;</a>

The Audience API is a service that retrieves aggregate interests and demographic insights for a collection of Twitter users. For information on the Audience API, see our documentation at http://support.gnip.com/apis/audience_api/. 

This example Audience API Client helps automate the creation of Segments and Audiences, and querying Audiences with [custom demographic 'groupings'](#audience-groupings). By providing Segment and Audience names, along with the numeric User ID of an account of interest, you can build and query an audience with a single run of the client. If you have authorized access, you can do the same with the Twitter users that have engaged or seen Tweets of an account of interest over the previous 90 days. For building Segments with customer user collections, one key feature of the Client is its ability to extract User IDs from a variety of sources. These sources include Gnip [Full-Archive Search](http://support.gnip.com/apis/search_full_archive_api/), [30-Day Search](http://support.gnip.com/apis/search_api/), or [Historical PowerTrack](http://support.gnip.com/apis/historical_api/) products, the [Twitter Public API](https://dev.twitter.com/rest/reference/get/followers/ids), and simple CSV files.

The Audience API requires OAuth authentication and Twitter consumer and access tokens. A first step is getting access to the Audience API and creating a Twitter App used to authenticate. See the [Getting Started](#getting-started) section below for more information. 

The Client's design was driven by some common ['usage patterns'](#example-usage-patterns) employed while creating and querying Audiences. These range from creating multiple user Segments from different collections of User IDs, to repeatedly querying an Audience once it is created. This Client provides a set of helper features for working with the Audience API:

+ Provides command-line parameters for easily building Segments based on account followers, engaged users, and impressed users by passing in the numeric User ID.
+ Provides a set of methods for building Segments from a variety of User ID sources.
+ Managing Segments and Audience by name. 
  + The Audience API natively identifies and manages Segment and Audiences with universally-unique IDs (UUID). An example ID is ```132a19a9-4448-4273-9317-69c17b2ae794```.
  + When creating a Segment or Audience, a human-readable name is provided and associated with it. This name is included in the metadata returned when making API GET requests for Audience and Segments.  
  + This Client provides methods for retrieving, updating, and deleting Segments and Audiences by name.  
+ Abstracts away some of the 'lower-level' API details:
  + Manages the creation of Segments with more than 100K users. You can import a collection consisting of millions of users, and this client will manage the multiple 'add user' requests required to build the Segment 100K users per request.
  + When adding Segments to an existing Audience, the Client manages the update process by retrieving the Audience composition of Segments, deleting the Audience, and re-creating the Audience with the updated list of Segments.
+ Provides an option to inject the [Audience metadata](#add-audience-metadata) into query results. This option can help you keep track of what Audiences different results were based on.
+ If making multiple Audience queries based on different [Audience Grouping](#audience-groupings), the results' filenames are serialized.
 
The API Client has several modes:

+ Manage Segments and Audiences.

    Building Segments:
    
    + Build Segment based on User ID collection (```-c``` command-line option, or ```segment_build_mode: collection``` config file option, triggers data import from inbox).
    + Build Segment based on followers of the specified account (```-f numeric_user_id``` command-line option, or ```segment_build_mode: followed``` config file option).
    
    These two option required access token permissions for the specified account:
    
    + Build Segment based on engaged users of the specified account (```-e numeric_user_id``` command-line option, or ```segment_build_mode: engaged``` config file option).
    + Build Segment based on impressed users of the specified account (```-i numeric_user_id``` command-line option, or ```segment_build_mode: impressed``` config file options).
    
    If Segments are not being built, the client will retrieve the specified Audience (via config file or command-line) and query it.
        
+ List all defined Segments and Audiences (```-l``` command-line option).
+ Print Audience API usage data (```-u``` command-line option).
+ Delete specified Segments and/or Audience. (```-d``` command-line option).

### User-story <a id="user-story" class="tall">&nbsp;</a>

As a Gnip customer who is adopting the Audience API: 

+ I want to automate the generation of Segments and Audiences. 
    + Given a set of Twitter tokens, manages the OAuth process.
    + Manage building Segments based on the followers of any account. 
    + Manage building Segments with potentially millions of User IDs.

+ I have collections of User IDs and want to easily build Audiences based on them. These collections consist of:
    + JSON User ID arrays generated from the [Twitter GET followers/ids endpoint](https://dev.twitter.com/rest/reference/get/followers/ids).
    + Tweets collected with a Gnip Product such as [Full-Archive Search](http://support.gnip.com/apis/search_full_archive_api/), [30-Day Search](http://support.gnip.com/apis/search_api/), or [Historical PowerTrack](http://support.gnip.com/apis/historical_api/).
        + If extracting User IDs from Tweets, the Client handles both 'original' and Activity Stream Tweet formats.
    + A simple CSV file generated from a datastore.
    
+ I need a client that helps create, update, and delete Segments and Audiences.  
    + From whatever source, this client extracts User IDs and loads them into new or existing Segments.
        + Manages limit of 100K User IDs per 'add users' API request.
    + Creates Audiences and assigns Segments to it.
    + I want to manage these objects by name, rather than UUIDs.

+ Once an Audience is created (made up of one or more Segments), I want an easy way to query that Audience with 
custom [Audience Groupings](#audience-groupings).

### Managing Segments and Audiences <a id="managing-segments-and-audiences" class="tall">&nbsp;</a>

To build an Audience, you first create user Segments. A user Segment is a collection of Twitter User IDs. An Audience 
may be comprised of a single Segment, or multiple Segments.

Driven by command-line options, configuration settings, and the availability of input data files, this client helps manage a set of Audience API 'sessions'. Examples of these work sessions include:

+ Building Segments based on users that follow, have engaged with, or been impressed by a specified Twitter account.
+ Building Segments from collections of User IDs.
+ Having a collection of User IDs, building a Segment and an Audience, and querying that Audience in a single session.
+ Adding a new Segment to an existing Audience.
+ Querying an Audience repeatedly with dynamic Audience API demographic [Groupings](#audience-groupings).

Three details fundamentally drive the client's execution logic:

+ Options provided for building a Segment:
    + Build mode can is specified in the app_settings.yaml file and can be overridden with the -c, -f, -e, and -i command-line parameters.
        + ```-f numeric_user_id``` or ```build_mode: followed```
        + ```-e numeric_user_id``` or ```build_mode: engaged```
        + ```-i numeric_user_id``` or ```build_mode: impressed```
        + ```-c``` or ```build_mode: collection```

When using the ```collection`` build mode, the client will look for files in the 'inbox':
        + If files are present, this client will attempt to build a Segment with specified name. Client treats all files in the inbox as a single User ID collection to be loaded into a single Segment. When constructing multiple Segments, you will iteratively move data files into the inbox, construct a Segment, repeat. 
        + Once files are parsed they are moved into a (auto-created) '/processed' directory.   
        + If files are not present, no Segments are created. 
    
+ **Segment name(s):**
    + Segment name is specified in app_settings.yaml file and can be overridden with the -s command-line parameter. 
    + Multiple Segment names per session are supported. Segments names need to be comma-delimited, as in "first_segment, second_segment".
    + If Segment name is _not provided_ (set to an empty "" string, "nil", or "none"), no Segment management is done, and the client moves on to working with an existing Audience. _If you are finished constructing Segments and assigning Segments to Audiences, then you should not specify a Segment name._
    + If a single Segment name _is provided_ the Client performs Segment requests. 
        + If data files _are_ found in the inbox, extracted User IDs are added to the specified Segment. If that Segment does not exist, it is created. If the Segment already exists, it is retrieved and the new User IDs are added to it. 
        + If files _are not_ provided, the Client will attempt to retrieve the specified Segment.
    + If multiple Segment names are provided the Client performs Segment requests. 
        + If data files _are not provided_, the specified Segments are added to the specified Audience if they are not already associated with the Audience. This mode is essential if you are building an Audience with Segments that are all under the minimum Audience size.
        + If data files _are provided_, extracted IDs are added to the __first__ Segment specified. The remaining Segments are added to the specified Audience if they are not already associated with the Audience.

+ **Audience name:** 
    + Audience name is specified in app_settings.yaml file and can be overridden with the -n command-line parameter.
    + One Audience name per session is supported.
    + If Audience name is _not provided_ (set to an empty string, nil, or 'none' [TODO]), no Audience management is done, and the client exits after any Segment management. _If you are not creating or querying Audiences, then you should not specify an Audience name._
    + If a Audience name _is provided_ the Client performs Audience requests.
        + If the Audience does not exist, it is created with the Segments created or retrieved during Segment management.       
        + Each Segment specified is added to the Audience if it does not already reference the Segment.
        + Audience is queried with configured Audience Groups.

The above processing logic is encapsulated in the audience_app.rb script. So, if you want to add or change behavior, start there. The underlying [Audience client class](#audience-client) encapsulates all the helper methods to work with the API, and other apps can be written 'on top' of that.

### Example Usage Patterns <a id="example-usage-patterns" class="tall">&nbsp;</a>
 

+ **Building Segment based on followers of a specified account, build an Audience with that single Segment, and query the Audience.**

For this example, an Audience will be built and queried based on my @snowman account. Since this account has more than 500 followers, we can build a single Segment based on these followers, create an Audience with that single Segment, and then query that Audience... all in a single run.

Building a Segment based on an account's followers is very straightforward. You need to specify names for the Segment and Audience, provide the numeric account ID for the @snowman account, and set your demographic Groupings of choice. These can all be set in the app_settings.yaml file, and you can also provide the names and User ID via the command-line.

+ Steps to do this:
    + Configuration details:
        + Segment name: snowman_followers
        + Audience name: snow_audience
        + build_mode: followed
              
              
    + Run client: ```$ruby audience_app.rb```
        + if using command-line, you can alternatively call with parameters: ```-n "snowman_audience" -s "snowman_followers" -f 17200003``` 

    + Confirm Segment exists: ```$ruby audience_app.rb -l```

Expected output:

```  
Starting build process at 2016-07-13 08:26:30 -0600
Starting Segment management...
Created snowman_followed Segment with ID f8114329-83e5-4b01-a5c6-3a9b1e46370a.
Retrieving Segment(s): snowman_followed
Starting Audience management...
Audience snowman_audience does not exist... 
Have 511 User IDs in Segments.
Created 'snow_audience' Audience with 1 Segments. Audience ID: 00ac9afa-a0e7-4515-803a-f91bd9668d8e
Request: {"name":"snowman_audience","segment_ids":["f8114329-83e5-4b01-a5c6-3a9b1e46370a"]}
Querying Audience...
Audience metadata:
<<results here>>
Finished at 2016-07-13 08:26:52 -0600
```    

+ **Building Segment from a collection of User IDs.**

Building a Segment requires a collection of Twitter User IDs. This Client can parse and extract IDs from several sources such as [Historical PowerTrack](http://support.gnip.com/apis/historical_api/) files, [30-Day](http://support.gnip.com/apis/search_api/) or [Full-Archive Search](http://support.gnip.com/apis/search_full_archive_api/) responses and [Twitter Public API](https://dev.twitter.com/rest/reference/get/followers/ids) responses.

+ Steps to do this:
    + Configuration details:
        + Segment name: Redrocks
        + Audience name: none
              + + if using command-line, call with parameters: ```-n "none" -s "Redrocks" ```+ 
        + inbox: ./inbox
    + Place data files with IDs in inbox.
    + Run client: ```$ruby audience_app.rb```
    + Confirm Segment exists: ```$ruby audience_app.rb -l```

Expected output:

```     
Starting build process at 2016-01-28 12:17:30 -0700
Starting Segment management...
Checking inbox for files to process...
Found JSON or GZ files to process... Parsing out User IDs...
Parsing files in inbox. Loading metadata: ["user_ids"]
Have 4 files to process...
Processing ./inbox/redrocksfollowers1.json... 
Processing ./inbox/redrocksfollowers2.json... 
Processing ./inbox/redrocksfollowers3.json... 
Processing ./inbox/redrocksfollowers4.json... 
Parsed 20000 User IDs...
De-duplicating User ID list. Have 15005 unique User IDs...
Creating or updating Segment Redrocks and adding User IDs...
Created Redrocks Segment.
Have 15005 User IDs.
Added 15005 User IDs to Redrocks.
No Audience to query, no more work to do...
Finished at 2016-01-28 12:17:35 -0700
```    

You may find yourself in a mode when you need to construct several Segments based on different collections of User IDs. When in this mode, an ID collection (a set of data files) is dropped into the inbox, the Segment name is provided, and the client executed as above. The data files are moved out of the inbox into a 'processed' subfolder. Then a fresh set of data files are dropped into the inbox, a fresh Segment name is specfied, and the client re-executed. To help automate the process remember you can pass in the Segment name via the command-line (which overrides any name specified in the configuration file), as in ```$ruby audience_app.rb -s my_second_segment```  

Notes:
    In the above example, while no configuration files are specified when running the client app, by default it looks for them in a ./config directory. The default file names are app_settings.yaml and accounts.yaml. If you want, you can specify your custom locations and names with command-line parameters:  ```$ruby audience_app.rb -a ./config/private/my_account.yaml -c ./config/shared/app_settings.yaml```       

+ **Having a collection of User IDs, building a Segment and an Audience, and querying that Audience in one sequence.**
 
+ Steps to do this:
    + Configuration details:
        + Segment name: a_bunch_of_skiers
        + Audience name: think_snow
          + + if using command-line, call with parameters: ```-n "think_snow" -s "a_bunch_of_skiers" ``` 
        + inbox: ./inbox
    + Place data files with IDs in inbox.
    + Run client: ```$ruby audience_app.rb```
    + Review results.

Expected output:

```
Starting build process at 2016-01-28 12:23:43 -0700
Starting Segment management...
Checking inbox for files to process...
Found CSVs... Parsing out User IDs...
Have 1 file to process...
Loaded 113873 User IDs...
Creating or updating Segment a_bunch_of_skiers and adding User IDs...
Created a_bunch_of_skiers Segment.
Have 113873 User IDs.
Dividing User list into sets of 100000 User IDs.
Have 2 sets of User IDs groups.
Added 100000 User IDs to a_bunch_of_skiers.
Added 13873 User IDs to a_bunch_of_skiers.
Retrieving Segment(s): a_bunch_of_skiers
Starting Audience management...
Audience think_snow does not exist... 
Have 113873 User IDs in Segments.
Created 'think_snow' Audience with 1 Segment.
Querying Audience...

Audience metadata:
<<results here>>
Finished at 2016-01-28 12:24:07 -0700
```

The Audience name can also be passed in via the command-line with the -n parameter. Remember, the command-line parameter overrides any name it finds in the app_settings.yaml configuration file. 

Note that to run the client in this mode, where a single Segment is used to create an Audience, the Segment must have at least the minimum amount of User IDs required to create an Audience (500). If you attempt to build an Audience with a single Segment with less than the required minimum, here is the expected output:

```
Starting build process at 2016-01-28 12:46:10 -0700
Starting Segment management...
Checking inbox for files to process...
Found JSON or GZ files to process... Parsing out User IDs...
Parsing files in inbox. Loading metadata: ["user_ids"]
Have 1 files to process...
Processing ./inbox/some_user_ids.json... 
Parsed 6000 User IDs...
De-duplicating User ID list. Have 5000 unique User IDs...
Creating or updating Segment small_segment and adding User IDs...
Created small_segment Segment.
Have 5000 User IDs.
Added 5000 User IDs to small_segment.
Retrieving Segment(s): small_segment
Starting Audience management...
Audience new_audience does not exist... 
Not enough User IDs to create an Audience. Minimum required is 500, but only 400 in Segments.
No Audience to query, no more work to do...
Finished at 2016-01-28 12:46:17 -0700
```

See the next example work-flow for more details on building Audiences with a set of Segments all with less with the minimum required to build an Audience.

+ **Building an Audience from multiple Segments, all with fewer than the minimum required to create an Audience.**

In this example, there are two collections of User IDs, each with 400 User IDs. The usage pattern of building a single Segment from a collection of User IDs and creating an Audience in a single session is not possible since each Segment has less than the required minimum amount of User IDs. Instead, you can first create the Segments, then reference the two Segments when creating the Audience. In the example, we'll combine the last two steps into a single session: build the second Segment, add it and the first Segment to create the new Audience, then query it.  

First, build the first Segment:

  + Configuration details:
        + Segment names: my_first_segment
        + Audience name: none
          + if using command-line, call with parameters: ```-n "none" -s "first_small_segment" ``` 
        + inbox: ./inbox
  + Place first User IDs collection in the inbox.
  + Run client: ```$ruby audience_app.rb -m```   (-m is optional as it is the default mode)

Expected Output:

```
Starting build process at 2016-01-28 14:13:36 -0700
Starting Segment management...
Checking inbox for files to process...
Found JSON or GZ files to process... Parsing out User IDs...
Parsing files in inbox. Loading metadata: ["user_ids"]
Have 1 files to process...
Processing ./inbox/user_ids.json... 
Parsed 400 User IDs...
De-duplicating User ID list. Have 400 unique User IDs...
Creating or updating Segment first_small_segment and adding User IDs...
Created first_small_segment Segment.
Have 400 User IDs.
Added 400 User IDs to first_small_segment.
No Audience to query, no more work to do...
Finished at 2016-01-28 14:13:40 -0700
```
  
Second, build the second Segment, and add it and the first Segment to the new Audience, then query it:

+ Configuration details:
        + Segment names: second_small_segment, first_small_segment
        + Audience name: big_enough_audience
          + if using command-line, call with parameters: ```-n "big_enough_audience" -s "second_small_segment, first_small_segment" ``` 
        + inbox: ./inbox
  + Place second User IDs collection in the inbox.
  + Run client: ```$ruby audience_app.rb``` 
   
Expected Output:

```
Starting build process at 2016-01-28 15:07:26 -0700
Starting Segment management...
Checking inbox for files to process...
Found JSON or GZ files to process... Parsing out User IDs...
Parsing files in inbox. Loading metadata: ["user_ids"]
Have 1 files to process...
Processing ./inbox/redrocksfollowers4.json... 
Parsed 400 User IDs...
De-duplicating User ID list. Have 400 unique User IDs...
Creating or updating Segment second_small_segment and adding User IDs...
Created second_small_segment Segment.
Have 400 User IDs.
Added 400 User IDs to second_small_segment.
Retrieving Segment(s): second_small_segment, first_small_segment
Starting Audience management...
Audience big_enough_audience does not exist... 
Have 800 User IDs in Segments.
Created 'big_enough_audience' Audience with 2 Segments.
Querying Audience...

Audience metadata:
<<results here>>

Finished at 2016-01-28 15:07:40 -0700
```

+ **Adding a Segment to an existing Audience.**

After creating an Audience, you may decide to add more Segments to it. When adding a Segment, you can build it on the fly with a collection of User IDs, or simply add an existing unlocked Segment. 

+ Steps to do this:
    + Configuration details:
        + Segment name: my_new_segment
        + Audience name: my_existing_audience
              + + if using command-line, call with parameters: ```-n "my_existing_audience -s "my_new_segment" ```
        + outbox: ./outbox
  
    + Run client: ```$ruby audience_app.rb```
    + Review results written to 'outbox' directory.
    
Expected output:

```
Starting build process at 2016-06-09 14:44:17 -0600
Starting Segment management...
Checking inbox for files to process...
Found JSON or GZ files to process... Parsing out user_ids...
Parsing files in inbox. Loading metadata: ["user_ids"]
Have 19 files to process...

Parsed 202 User IDs...
De-duplicating User ID list. Have 59 unique User IDs...
Creating or updating Segment my_new_segment and adding User IDs...
Created my_new_segment Segment with ID 53e7a7d1-bf11-49b0-b9ae-b6f925199842.
Have 59 User IDs.
Added 59 User IDs to my_new_segment.
Retrieving Segment(s): my_new_segment
Starting Audience management...
Adding Segment to Audience.
Created 'my_existing_audience' Audience with 2 Segments. 
Querying Audience...

Audience metadata:
<<results here>>

```

+ **Querying an Audience repeatedly with dynamic Audience API demographic Groupings.**
 
Once an Audience is created, you will probably get in the mode where you repeatedly query with changing [Audience Groupings](#audience-groupings). In this example, we've created an Audience named 'think_snow' that is made of up several Segments.

+ Steps to do this:
    + Configuration details:
        + Segment name: none (or empty string)
        + Audience name: think_snow
              + + if using command-line, call with parameters: ```-n "think_snow -s "none" ```
        + outbox: ./outbox
  
    + Update [Audience Groupings](#audience-groupings) with demographic groupings.
    + Run client: ```$ruby audience_app.rb```
    + Review results written to 'outbox' directory.
    
Expected output:

```
Starting build process at 2016-01-28 15:28:29 -0700
Checking inbox for files to process...
No new User IDs to process...
Starting Audience management...
No Segments to add to Audience.
Querying Audience...

Audience metadata:
<<results here>>

Finished at 2016-01-28 15:28:34 -0700
```

Note: There is an option to [inject Audience metadata](#client-output) into the query results JSON.

+ **Deleting Segments and Audiences.**

In time you'll probably want to delete Segments and Audiences. Note that you can delete Segments that an Audience is constructed with without affecting the Audience. 
 
This example client supports deleting Segments and Audiences by name. In this example, we'll delete a Segment named 'my-old-segment' and an Audience named 'my-old-audience'.

+ Steps to do this:
    + Configuration details:
        + Segment name: my-old-segment
        + Audience name: my-old-audience
              + if using command-line, call with parameters: ```-n "my-old-audience" -s "my-old-segment" ```
 
    + Run client: ```$ruby audience_app.rb```
        + if using command-line, call with parameters: ```-n "my-old-audience" -s "my-old-segment" ```
 
     
    
Expected output:

```
Deleted Segment my-old-segment...
Deleted Audience my-old-audience...
```

## Getting started <a id="getting-started" class="tall">&nbsp;</a>

+ Obtain App access to the Audience API from Twitter via Gnip.
+ Create a Twitter App at https://apps.twitter.com, and generate OAuth Keys and Access Tokens.
+ Compile a collection of Twitter User IDs.
+ Deploy client code
    + Clone this repository.
    + Using the Gemfile, run bundle
+ Configure both the Accounts and App configuration files.
    + Config ```accounts.yaml``` file with OAuth keys and tokens.
    + Config ```app_settings.yaml``` file with processing options, Audience Groupings.
    + See the [Configuring Client](#configuring-client) section for the details.
+ Execute the Client using [command-line options](#command-line-options).
    + To confirm everything is ready to go, you can run the following command:

    ```
    $ruby audience_app.rb -l
    ```
    You should see a listing of Segments and Audiences, which when you are just starting out will be an empty list. 

### Configuring Client <a id="configuring-client" class="tall">&nbsp;</a>

There are two files used to configure the Audience API client:

+ Account settings: holds your OAuth consumer keys and access tokens. The Audience API requires 3-legged authorization 
for all endpoints. Additionally, Twitter must approve your client application before you can access the API.
    + Defaults to ./config/account.yaml
    + alternate file name and location can be specified on the command-line with the -a (account) parameter.
    
+ Application settings: used to specify the names of the Audience you are building or querying, the Segment name you are 
building (if you are ingesting User IDs), several application options, as well as the query Groupings.
    + Defaults to ./config/app_settings.yaml.
    + Alternate file name and location can be specified on the command-line with the -c (config) parameter.
    
So, if you are using different file names and paths, you can specify them with the -a and -c command-line parameters:

```
  $ruby audience_app.rb -l -a "./my_path/my_account.yaml" -c "./my_path/my_settings.yaml"
```


#### Account Configuration - ```accounts.yaml``` <a id="account-configuration" class="tall">&nbsp;</a>

Holds your OAuth consumer keys and access tokens. The Audience API requires 3-legged authorization 
for all endpoints. Additionally, Twitter must approve your client application before you can access the API.

```
#OAuth tokens and key for Audience API.
audience_api:
  
  consumer_key:
  consumer_secret:
  
  #Access token/secret
  access_token:
  access_token_secret:
  
  app_id:  #Not used in code, but useful troubleshooting information.
  
```

#### App Settings Configuration - ```app_settings.yaml``` <a id="app-settings-configuration" class="tall">&nbsp;</a>

This file is used to configure [application options](#application-options), [Audience Groupings](#audience-groupings) and [logging](#logging) options.

##### Application options <a id="application-options" class="tall">&nbsp;</a>

Used to specify the names of the Audience you are building or querying, the Segment name you are building (if you are ingesting User IDs), several application options, as well as the query Groupings.

```
#Audience API ------------------------
audience_settings:
  audience_name: flood_audience
  segment_name: flood_segment #If loading User IDs, one Segment will be built based on all imported User IDs.

  inbox: ./inbox  #Where User ID data files go (HPT Tweet files? Search Tweet JSON?, Public API User ID JSON array? Database CSV export?)
  verbose: true #Over-ridden by command-line option...

  outbox: './outbox' #Audience query results go here.
  serialize_output: false #Serialze output file names, results.json, results_1.json, etc.
  add_audience_metadata: true #Inject Audience metadata into results JSON.
```  

##### Audience Groupings <a id="audience-groupings" class="tall">&nbsp;</a>

For more details on specifying the demographics see the [Audience API documentation](http://support.gnip.com/apis/audience_api/interpreting_insights.html#Definitions).

```
audience_groupings: #Two model levels per group are supported. Up to ten Groupings per audience query.
  country_and_gender:
    group_by:
      - user.location.country
      - user.gender
  language:
    group_by:
      - user.language
  interests:
    group_by:
      - user.interest
  tv_show_types:
    group_by:
      - user.tv.genre
  country_and_region:
    group_by:
       - user.location.country
       - user.location.region
  service_and_os:
    group_by:
       - user.device.network
       - user.device.os
  service:
      group_by:
         - user.device.network
```

##### Logging <a id="logging" class="tall">&nbsp;</a>

This Client uses (mixes-in) a simple AppLogger module based on the 'logging' gem. This singleton 
object is thus shared by the Client app and its helper objects. If you need to implement a different logging design,
that should be pretty straightforward... Just replace the `AppLogger.log` calls with your own logging signature. 

The logging system maintains a rolling set of files with a custom base filename, directory, and maximum size. 

The `app_settings.yaml` file contains the following logging settings:

```
logging:
  name: audience_app.log
  log_path: ./log
  warn_level: debug
  size: 1 #MB
  keep: 2
```  

#### Command-line Options <a id="command-line-options" class="tall">&nbsp;</a>

The Client supports the command-line parameters listed below. Either the single-letter or verbose version of the parameter can be used. 

+    -a, --account -->           Account configuration file (including path) that provides API keys for access.
+    -c, --config -->             Settings configuration file (including path) that provides app settings.
+    -n, --name -->                 The name of the 'target' Audience being built/updated/queried. 
+    -s, --segment -->           The name of the 'target' Segment being built/updated and added to the 'target' Audience.
+ 
+    -m, --manage -->             Manage Segments and Audiences (Create, Build, Query).
+    -l, --list -->                      List all defined Audiences and Segments.
+    -u, --usage -->                     List Audience API usage data.
+    -d, --delete -->                    DELETE configured Audience and Segment.

+    -v, --verbose -->                   When verbose, output all kinds of things, each request, most responses, etc.
+    -h, --help -->                      Display this screen.

Command-line parameters override any equivalent settings found in the app_settings.yaml configuration file. For example:

+ -n overrides audience_name:
+ -s overrides segment_name: 
+ -v overrides verbose:
+ -a overrides the default of ./config/accounts.yaml
+ -c overrides the default of ./config/app_settings.yaml


##### Command-line examples

Here are some command-line examples to help illustrate how they work:

+ Pass in custom configuration file names/paths and print a list of my current Segments and Audiences. 

  ```$ ruby audience_app.rb -a "./my_path/my_account.yaml" -c "./my_path/my_settings.yaml" -l```

+ Using the default config file names and locations: 
  + Create a Segment named 'new_segment' (overriding any Segment name specified in config file) based on the current 'inbox' files
  + Add that Segment to an Audience named 'this_audience' and query it. If 'this_audience' already exists, it will be retrieved, and updated with the new Segment. Otherwise, a new Audience will be created.
  + Write the results to the 'outbox' as specified in the app_settings.yaml file.
   
  ```$ ruby audience_app.rb -s "new_segment" -n "this_audience"```

+ My Audience is all set, just query it with my current [Audience Groupings](#audience-groupings). 
  ```$ ruby audience_app.rb -s -n "this_audience"```


### Client Output <a id="client-output" class="tall">&nbsp;</a>

When the Client queries an Audience, it writes the API response to the 'outbox' folder as configured in the app_settings.yaml file. The output file names are based on the Audience name with '_results.json' appended to it. For example, if you query an Audience named 'my_first_audience' the query results will be written to a 'my_first_audience_results.json' file. If an Audience is repeatedly queried (usually with an updated set of [Audience Groupings](#audience_groupings)), the output file name is numerically serialized. For example, if the 'my_first_audience' is queried a second time, the output file is named 'my_first_audience_results_2.json'.

<a id="add-audience-metadata" class="tall">&nbsp;</a>
There is an ```add_audience_metadata``` option to inject the Audience metadata into these results. This can help track what Audiences different results were based on. When set to 'true' the current Audience metadata is included in the results JSON under an 'audience' key. These metadata are the result of the [Audience API GET /insights/audience/audiences/:id] (http://support.gnip.com/apis/audience_api/api_reference.html#GetAudiencesID) response.

```
{
  "audience": {
    "id": "9c0786aa-c097-4f29-9d79-1a24ebd415f1",
    "name": "flood",
    "created": "2016-01-15T16:58:29Z",
    "last_modified": "2016-01-15T16:58:29Z",
    "num_user_ids": "113873",
    "num_distinct_user_ids": "113873",
    "state": "available",
    "segment_ids": [
      "f60a3b9b-d4b8-4d1e-ba84-f8853999b705"
    ],
    "segment_names": [
      "flood"
    ]
  }
}
```

### Other Details <a id="other-details" class="tall">&nbsp;</a>

#### Ingesting User IDs <a id="ingesting-user-ids" class="tall">&nbsp;</a>

The first step in creating an Audience is uploading User IDs into a Segment. This client is designed to ingest User IDs from several  sources:

+ [Gnip Historical PowerTrack](http://support.gnip.com/apis/historical_api/) files. These JSON files can be gzipped or uncompressed.
+ JSON responses from either of Gnip's Search products: [30-Day](http://support.gnip.com/apis/search_api/) or [Full-Archive](http://support.gnip.com/apis/search_full_archive_api/).
+ Simple text files with one User ID per line. User IDs stored in a database can easily be exported into such a file.
    + Format example:
    ```
        user_id
        1345638
        2345649
        3345659
    ```
+ JSON User ID arrays generated from the [Twitter GET followers/ids endpoint](https://dev.twitter.com/rest/reference/get/followers/ids).
    + JSON response from API: 
    ```
    {
      "ids": [
        1345638,    
        2345649,    
        3345659
    ],
    "next_cursor": 1.5063424781893e+18,
    "next_cursor_str": "1506342478189272987",
    "previous_cursor": 0,
    "previous_cursor_str": "0"
    }
    ```
These file types are placed in a configured 'inbox' folder. After these files are ingested, then are moved into a 'processed' subfolder (automatically created if necessary).

### Digging into the Code <a id="digging-into-the-code" class="tall">&nbsp;</a>

There are four Ruby files associated with this client (subject to change due to refactoring and more attention to "separating concerns"): 
+ audience_app.rb: <a id="audience-app" class="tall">&nbsp;</a>
    + Manages configuration files, command-line options and application session logic. Examples of these work session include:
        + Building Segments from collections of User IDs.
        + Having a collection of User IDs, building a Segment and an Audience, and querying that Audience.
        + Adding a new Segment to an existing Audience.
    + Creates one instance of the AudienceClient (audience_client.rb) class. 
    + 
    + Start here if you are adding/changing command-line details. 
    + No API requests are made directly from app.

+ /lib/audience_client.rb <a id="audience-client" class="tall">&nbsp;</a>
    + The intent here is to have this class encapsulate all the low-level understanding of exercising the Audience API.
    + Manages HTTP calls, OAuth, and generates all API request URLs.  
    + This class has constants such as:
        + MAX_USERS_PER_SEGMENT_UPLOAD = 100_000
        + MIN_USERS_PER_AUDIENCE = 500
        + MAX_USERS_PER_AUDIENCE = 30_000_000 
        + REQUESTS_PER_MINUTE = 12 
    + This class has and manages the following attributes:
        + A single array of User IDs.    
        + HTTP endpoint details.
        + A single set of app keys and access tokens.
        + Settings that map to the app_settings.yaml file.

+ /common/insights_utils.rb <a id="insights-utils" class="tall">&nbsp;</a>
    + A 'utilities' helper class with methods common to both Insights APIs, Audience and Engagement.
    + Where all extracting of IDs happens... Adding a new User IDs file type? Add a method here.
    + Code here can be shared with other Insights API clients, such as the Engagement client.

+ /common/app_logger.rb <a id="app-logger" class="tall">&nbsp;</a>
    + A singleton module that provides a basic logger. The above scripts/classes reference the AppLogger module.
    + Provides a verbose mode where info and error log statements are printed to Standard Out.
    + Current logging signature: 
        + ```AppLogger.log_info("I have some information to share")```
        + ```AppLogger.log_error("An error occurred: #{error.msg}")```
    
        If you have in-house logger conventions to implement it should be pretty straightforward to swap that in.    
        

#### Helper Methods and Features <a id="helper-methods" class="tall">&nbsp;</a>

This Audience API client provides a collection of helper methods. Examples include retrieving and deleting Segment and 
Audience objects by name instead of id. 

##### Helper methods
+ Segment methods
    + get_segment_by_name(name)
    + segment_name_exists?(name)
    + delete_segment_by_name(name)
+ Audience methods  
    + get_audience_by_name(name)
    + audience_name_exists?(name)
    + delete_audience_by_name(name)

##### Helper features
 + add_audience_metadata - configuration boolean. When true, Audience metadata is injected into results JSON. Therefore 
 as you archive results you'll have a snapshot of the Audience metadata that is associated with the results.


### License

Copyright 2016 Twitter, Inc. and contributors.

Licensed under the MIT License: https://opensource.org/licenses/MIT



