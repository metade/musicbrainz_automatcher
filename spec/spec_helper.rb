dir = File.dirname(__FILE__)
$LOAD_PATH.unshift "#{dir}/../lib"
 
require 'rubygems'
require 'spec'
require 'musicbrainz_automatcher'

Spec::Runner.configure do |config|
  config.mock_with :mocha
end

class MockRbrainzQuery
  attr_reader :track_queries
  attr_reader :artist_queries
  
  def initialize
    # Real MusicBrainz service, for when local fixture isn't available
    @query = MusicBrainz::Webservice::Query.new($musicbrainz_ws)
    @artist_queries = []
    @track_queries = []
  end

  def fixture_path( *params )
    filename = params.join('__').downcase
    filename.gsub!(/\\/, '')
    filename.gsub!(/[^a-z0-9\-]/, '_')
    return File.join(File.dirname(__FILE__),'fixtures','rbrainz',filename+'.yaml')
  end

  def load_fixture( *params, &block )
    filepath = fixture_path( *params )
    if File.exists?(filepath)
      return YAML::load( File.read(filepath) )
    else
      # No fixture exists, create one:
      puts "Writing new fixture: #{filepath}"
      response = block.call
      File.open(filepath, 'w') { |file| file.puts YAML::dump( response ) }
      return response
    end
  end

  def get_tracks(filter)
    query = filter.instance_variable_get('@filter')[:query]
    artist = query.match(/artist:\((.+?)\)/)[1]
    title = query.match(/ track:(.+)$/)[1]
    @track_queries << [artist,title]
    load_fixture(artist,title) do
      # If no fixture is available, do this:
      @query.get_tracks(filter)
    end
  end

  def get_artists(filter)
    artist = filter.instance_variable_get('@filter')[:name]
    @artist_queries << artist
    load_fixture(artist) do
      # If no fixture is available, do this:
      @query.get_artists(filter)
    end
  end

  def get_artist_by_id(mbid, includes=nil)
    load_fixture(mbid) do
      # If no fixture is available, do this:
      @query.get_artist_by_id(mbid, includes)
    end
  end
end
