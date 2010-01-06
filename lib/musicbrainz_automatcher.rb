require 'active_support'
require 'rbrainz'
require 'iconv'
require 'text'

# Monkey patch String class to add our escaping method
class String
  def lucene_escape_query
    return self.gsub(/([+\-|!(){}\[\]\^'"~*?:\\])/) {|s| '\\'+s}
  end
end

# Class to automatically match an artist and track to a MusicBrainz artist
class MusicbrainzAutomatcher
  attr_accessor :logger
  attr_accessor :network_timeout
  attr_accessor :network_retries
  attr_reader :cache
  attr_reader :mbws
  
  def initialize(options={})
    # Configuration options
    @network_timeout = options[:network_timeout] || 15  # seconds
    @network_retries = options[:network_retries] || 3
    
    # Create MusicBrainz webservice
    host = options[:musicbrainz_host] || 'musicbrainz.org'
    @mbws = MusicBrainz::Webservice::Webservice.new(:host => host, :proxy => options[:proxy])
    @mbws.open_timeout = @network_timeout
    @mbws.read_timeout = @network_timeout
    
    # Create a query cache
    @cache = ActiveSupport::Cache.lookup_store(options[:cache_type] || :memory_store)
    
    # Create a logger
    @logger = options[:logger] || Logger.new(STDOUT)
  end


  # Given an array of artists and a track title, return an rbrainz artist object.
  # If there is no match in MusicBrainz, then false is returned
  def match_artist(artists, title=nil)
  
    # Only interested in first item of title array
    title = title.first if title.is_a?(Array)

    # Remove excess whitespace from the title
    title.strip! unless title.nil?
    
    # Clean and split the artist names
    artists = clean_artists( artists )
    
    # Return false if no artist names given
    return false if artists.empty?

    # Set title to nil, if it is an empty string
    title = nil if !title.nil? and title.size<1
  
    # Perform the query if it isn't already cached
    artist = join_artists( artists )
    do_cached( "artists=#{artist} title=#{title}" ) do
    
      # Remove items from the artist array until we get a match
      mbartist_id = false
        
      ## Ignore if artist name contains two consecutive stars (they contain a sware words)
      unless artist =~ /\*\*/

        ## First: lookup based on track name and artist
        unless title.nil?
          mbartist_id = lookup_by_track( artist, title ) 
        
          ## Second: try removing brackets from the track name
          if !mbartist_id
            matches = title.match(/^(.+)\s+\(.+\)$/)
            mbartist_id = lookup_by_track( artist, matches[1] ) unless matches.nil?
          end
        end

        ## Third: look-up just based on artist name
        # (but not after we have removed an artist from the stack)
        if !mbartist_id
          # Also cache the lookup, just based on the artist name
          mbartist_id = do_cached( "artist_name=#{artist}" ) do
            lookup_by_artist( artist ) 
          end
        end
      end
    
      # Response is the MusicBrainz ID
      mbartist_id
    end

  end
  
  protected
  
  ## Perform a block if key isn't already cached.
  def do_cached( key, &block )
    # have a look in the cache
    value = @cache.fetch( key )

    # Cache HIT?
    return value unless value.nil?

    # Cache MISS : execute the block
    value = block.call( key )
    
    # Store value in the cache
    return @cache.write( key, value, :expires_at => Time.parse("18:00"))
  end
  
  # Clean up the artist name array
  def clean_artists(artists)
    
    # Turn the artists into an array, if it isn't already
    artists = [artists] unless artists.is_a?(Array)

    # Split up artist names
    artists.map! { |a| a.split(/\s+featuring\s+/i) }.flatten!
    artists.map! { |a| a.split(/\s+feat\.?\s+/i) }.flatten!
    artists.map! { |a| a.split(/\s+ft\.?\s+/i) }.flatten!
    artists.map! { |a| a.split(/\s+vs\.?\s+/i) }.flatten!
    artists.map! { |a| a.split(/\//) }.flatten!
    artists.map! { |a| a.split(/\&/) }.flatten!
   
    # Remove whitespace from start and end of artist names
    artists.each {|a| a.strip! }
    
    # Delete any empty artist names
    artists.delete_if { |a| a.blank? }
    
    return artists
  end
  
  # Concatinate an array of artist names together into a single string
  def join_artists(array)
    return "" if array.nil? or array.size<1
    return array.last if array.size==1
    
    rest = array.slice(0,array.size-1).join(', ')
    rest += " and " if (rest.size>0)
    return rest+array.last
  end
  
  
  ## Remove accents, remove non-word characters, remove whitespace
  def compact_string(str)
    ascii = Iconv.iconv("ascii//IGNORE//TRANSLIT", "utf-8", str).join
    ascii.downcase!
    ascii.gsub!('&', ' and ')
    return ascii.gsub(/[\W_]+/, "")
  end
  
  
  # Return the highest of two numbers
  # Isn't there a ruby built-in to do this?
  def max(i1, i2)
    i1>i2 ? i1 : i2
  end

  # How similar are two strings?  
  def string_percent_similar(str1, str2)
    # Optimisation: Completely identical? (give it a 1% boost!)
    return 101 if str1 == str2

    # Catch iconv failures
    begin
      s1 = compact_string(str1)
      s2 = compact_string(str2)
    rescue Iconv::IllegalSequence
      # Not similar
      return 0
    end
    
    # Don't allow empty strings to match
    return 0 if s1.size==0 or s2.size==0
    
    # How similar are the two strings?
    distance = Text::Levenshtein::distance( s1, s2 )
    length = max( s1.size, s2.size ).to_f
    percent = ((length-distance.to_f)/length) * 100

    return percent
  end
  
  # Compare two artist names are return how similar they are (in percent)
  def artist_names_similarity(mbartist, artist_name2)
  
    # Compare the two arists names
    best_score = string_percent_similar( mbartist.name, artist_name2 )
    @logger.debug("Comparing artist '#{mbartist.name}' with '#{artist_name2}' : similarity=#{best_score.to_i}%")
    
    # Optimisation: can't do better than 100% similar
    return best_score if best_score >= 100
  
    # Fetch the artist's aliases
    aliases = get_artist_aliases(mbartist.id.uuid)

    # Compare with each of the aliases
    unless aliases.nil?
      aliases.each do |artist_alias|
        # Compare the artist alias name
        percent = string_percent_similar( artist_alias, artist_name2 )
        @logger.debug("Comparing alias '#{artist_alias}' with '#{artist_name2}' : similarity=#{percent.to_i}%")
        best_score = percent if (best_score < percent)
      end
    end
    
    return best_score
  end
  
  
  ## Lookup artist based on an artist and track name
  # Returns musicbrainz artist gid, or false if no match found
  def lookup_by_track(artist, title)
    @logger.info("Looking up '#{artist}' with track '#{title}'")

    # Create a new track filter
    filter = MusicbrainzAutomatcher::new_track_filter(artist, title)
    
    # Query MusicBrainz server, but catch any errors
    attempt = 0
    begin
      q = MusicBrainz::Webservice::Query.new(@mbws)
      results = q.get_tracks(filter)
    rescue Exception => e
      @logger.error("Error querying MusicBrainz for artist (attempt #{attempt}): #{e.inspect}")
      sleep((attempt+=1)**2)
      retry if attempt < @network_retries
      raise e
    end

    matched_mbid = false
    for result in results
      ## Abort if score is less than 75%
      break if (result.score < 75)

      @logger.debug("  Score: "+result.score.to_s)
      @logger.debug("   title: "+result.entity.title)
      @logger.debug("   artist: "+result.entity.artist.name)
      @logger.debug("   artist mbid: "+result.entity.artist.id.uuid)
      
      # Optimisation: skip if it is an artist we have already matched to
      next if matched_mbid == result.entity.artist.id.uuid
      
      # Compare the artist names
      if (artist_names_similarity(result.entity.artist, artist)<75)
        @logger.debug(" artist name similarity is less than 75%, skipping.")
        next
      end

      ## More than one artist?
      if (matched_mbid != result.entity.artist.id.uuid and matched_mbid)
        @logger.info("  Found more then one artist with a high score, giving up.")
        return false
      else
        matched_mbid = result.entity.artist.id.uuid
      end
    end

    # Did we find something?
    if matched_mbid
      ## Yay!
      @logger.info("  Matched to artist ID: #{matched_mbid}")
      return matched_mbid
    else
      # didn't find anything :(
      @logger.info("  Lookup by track failed")
      return false
    end
    
  end
  
  
  ## Lookup artist, just based on its name
  # Returns musicbrainz artist gid, or false if no match found
  def lookup_by_artist(name)
    @logger.info("Looking up '#{name}' just by name")
    
    filter = MusicBrainz::Webservice::ArtistFilter.new(
      :name => name,
      :limit => 20
    )
  
    # Query MusicBrainz server, but catch any errors
    attempt = 0
    begin
      q = MusicBrainz::Webservice::Query.new(@mbws)
      results = q.get_artists(filter)
    rescue Exception => e
      @logger.error("Error querying MusicBrainz for artist (attempt #{attempt}): #{e.inspect}")
      sleep((attempt+=1)**2)
      retry if attempt < @network_retries
      raise e
    end
    
    similarities = {}
    for result in results
      ## Give up if score is less than 50%
      break if (result.score < 50)

      ## Work out how similar the artist names are
      similarity = artist_names_similarity(result.entity, name).to_i
      next if similarity<=0
  
      ## Store it in the hash    
      @logger.debug("  Score: #{result.score}")
      @logger.debug("   name: #{result.entity.name}")
      @logger.debug("   similarity: #{similarity}")
      similarities[similarity] ||= [];
      similarities[similarity] << result.entity
    end
    
    if similarities.keys.size < 1
      @logger.info("  No matches found when looking up 'just by name")
      return false
    end
    
    ## Order by similarity
    most_similar = similarities.keys.sort.last
    if most_similar < 85
      @logger.info("  Closest match is less than 85% similar")
      return false
    elsif similarities[most_similar].length != 1
      @logger.info("  More then one shortest distance, giving up")
      return false
    else
      rbartist = similarities[most_similar].first
      @logger.debug("  Found artist by name: #{rbartist.id.uuid}")
      return rbartist.id.uuid
    end
  end
  
  def get_artist_aliases(mbid)
    # Hack to stop hitting the MusicBrainz server for Various Artists
    return [] if mbid == '89ad4ac3-39f7-470e-963a-56509c546377'
  
    attempt = 0
    begin
      q = MusicBrainz::Webservice::Query.new(@mbws)
      artist_includes = MusicBrainz::Webservice::ArtistIncludes.new( :aliases => true )
      response = q.get_artist_by_id(mbid, artist_includes)
      if response.nil?
        aliases = []
      else 
        aliases = response.aliases.map { |a| a.name }
      end
      
      # Add fake "The Artist" alias if it isn't already there
      if !response.nil? and response.name !~ /^The /i and !aliases.include?("The #{response.name}")
        aliases << "The #{response.name}"
      end

      return aliases
    rescue Exception => e
      @logger.error("Error querying MusicBrainz for artist aliases (attempt #{attempt}): #{e.inspect}")
      sleep((attempt+=1)**2)
      retry if attempt < @network_retries
      raise e
    end
  end


  ## A custom track filter, that uses a query more like the normal MusicBrainz search page 
  def self.new_track_filter(artist, title)
    # Escape the strings
    tterm = title.lucene_escape_query
    aterm = artist.lucene_escape_query
    
    filter = MusicBrainz::Webservice::TrackFilter.new(
      :query => "artist:(#{aterm})(sortname:(#{aterm}) alias:(#{aterm}) !artist:(#{aterm})) track:#{tterm}",
      :limit => 20
    )
  end
end
