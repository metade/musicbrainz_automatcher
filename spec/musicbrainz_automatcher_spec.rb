require 'spec_helper'

describe MusicbrainzAutomatcher do

  before(:each) do
    # Configure the MusicBrainz Automatcher
    @mbam = MusicbrainzAutomatcher.new({
      :musicbrainz_host => 'musicbrainz.org',
      :network_timeout => 1,
      :network_retries => 0
    })

    # Only display things that went wrong
    @mbam.logger = Logger.new(STDOUT)
    @mbam.logger.level = Logger::WARN
    
    # Mock out the MusicBrainz webservice
    @query = MockRbrainzQuery.new
    MusicBrainz::Webservice::Query.stubs(:new).returns(@query)
  end
  
  describe "when cleaning up a list of artist names" do
  
    def clean_artists(artists)
      @mbam.send(:clean_artists, artists)
    end
    
    it "should turn a single artist string into an array" do
      clean_artists("Artist A").should == ["Artist A"]
    end
    
    it "should leave an array of artists alone" do
      clean_artists(["Artist A", 'Artist B']).should == ["Artist A", 'Artist B']
    end

    it "should split up an artist name with 'ft.' in the middle" do
      clean_artists("Kate Nash ft. Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end

    it "should split up an artist name with 'feat' in the middle" do
      clean_artists("Kate Nash feat Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end

    it "should split up an artist name with 'featuring' in the middle" do
      clean_artists("John Legend featuring Andre 3000").should == ["John Legend", "Andre 3000"]
    end

    it "should split up an artist name with 'Ft' in the middle" do
      clean_artists("Kate Nash Ft Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end

    it "should split up an artist name with ' vs ' in the middle" do
      clean_artists("Kate Nash vs Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end
    
    it "should split up an artist name with ' vs. ' in the middle" do
      clean_artists("Kate Nash vs. Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end
    
    it "should split up an artist name with ' Vs ' in the middle" do
      clean_artists("Kate Nash Vs Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end
    
    it "should split up an artist name with '/' in the middle" do
      clean_artists("Kate Nash/Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end
    
    it "should split up an artist name with ' / ' in the middle" do
      clean_artists("Kate Nash / Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end
    
    it "should split up an artist name with '&' in the middle" do
      clean_artists("Kate Nash&Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end
    
    it "should split up an artist name with ' & ' in the middle" do
      clean_artists("Kate Nash & Jay-Z").should == ["Kate Nash", "Jay-Z"]
    end
    
    it "should remove whitespace from the start and end of artist names" do
      clean_artists(["    Kate Nash "]).should == ["Kate Nash"]
    end
   
    it "should remove empty elements from the artist names" do
      clean_artists(["","  ","   "]).should == []
    end
    
  end
  
  describe "getting list of artist aliases" do
 
    def get_artist_aliases(mbid)
      @mbam.send(:get_artist_aliases, mbid)
    end
  
    it "should add a fake 'The ' at the start of an artist with no aliases" do
      # Brookes Brothers
      get_artist_aliases('1ebfdf94-157b-47c0-a71e-9291c6a557cd').should == ['The Brookes Brothers']
    end
  
    it "should not return an extra 'The' for an artist with 'The ' at the start" do
      # The Automatic
      get_artist_aliases('afe5e238-d248-4da4-87b7-e70dfab787f6').should == []
    end
  
    it "should not add a fake 'The Artist' alias when there is already a 'The Artist' alias" do
      # Delays
      get_artist_aliases('f86d80f3-3d2e-4450-9b0c-638152e93df3').should == ['The Delays']
    end

    it "should return the aliases for an artist" do
      # Jay-Z
      get_artist_aliases('f82bcf78-5b69-4622-a5ef-73800768d9ac').should == ['Jay Z', 'Jayz', 'Jay - Z', 'Jaÿ-Z', 'The Jay-Z']
    end
  
  end
  
  describe "when auto-matching an artist" do

    it "should find artist id in first query for unambiguous single artist" do
      mbid = @mbam.match_artist( "Kate Nash", "Pumpkin Soup" )
      mbid.should == '49018fd2-95ef-4f7e-92bb-813159909314'
      @query.track_queries.should == [["Kate Nash", "Pumpkin Soup"]]
      @query.artist_queries.should == []
    end
    
    it "should fail to find an artist if the artist does not exist" do
      mbid = @mbam.match_artist( "AAAABBBBCCCCDDDD", "EEEEEEFFFFFGGGGG" )
      mbid.should be_false
      @query.track_queries.should == [["AAAABBBBCCCCDDDD", "EEEEEEFFFFFGGGGG"]]
      @query.artist_queries.should == ["AAAABBBBCCCCDDDD"]
    end
    
    it "should fail to find an artist for something that MusicBrainz scores highly, but it clearly wrong!" do
      mbid = @mbam.match_artist( "non existent artist", "non existent track" )
      mbid.should be_false
      @query.track_queries.should == [["non existent artist", "non existent track"]]
      @query.artist_queries.should == ["non existent artist"]
    end
     
    it "should fail if more than one artist is highly scored" do
      mbid = @mbam.match_artist( "Oasis", "People" )
      mbid.should be_false
      @query.track_queries.should == [["Oasis", "People"]]
      @query.artist_queries.should == ["Oasis"]
    end

    it "should find a match for an artist with accents when searching with accents" do
      mbid = @mbam.match_artist( "José González", "Down the Line" )
      mbid.should == 'cd8c5019-5d75-4d5c-bc28-e1e26a7dd5c8'
      @query.track_queries.should == [["José González", "Down the Line"]]
      @query.artist_queries.should == []
    end
    
    it "should find a match for an artist with accents when searching without accents" do
      mbid = @mbam.match_artist( "Jose Gonzalez", "Down the Line" )
      mbid.should == 'cd8c5019-5d75-4d5c-bc28-e1e26a7dd5c8'
      @query.track_queries.should == [["Jose Gonzalez", "Down the Line"]]
      @query.artist_queries.should == []
    end

    it "should find a match for an artist with punctuation their name" do
      mbid = @mbam.match_artist( "P!nk", "Get the Party Started" )
      mbid.should == 'f4d5cc07-3bc9-4836-9b15-88a08359bc63'
      @query.track_queries.should == [["P\\!nk", "Get the Party Started"]]
      @query.artist_queries.should == []
    end

    it "should find a match for an artist by their alias when there is no match by name" do
      mbid = @mbam.match_artist( "Tchaikovsky", "Swan Lake" )
      mbid.should == '9ddd7abc-9e1b-471d-8031-583bc6bc8be9'
      @query.track_queries.should == [["Tchaikovsky", "Swan Lake"]]
      @query.artist_queries.should == []
    end

    it "should join the array of artist names together and find an artist match" do
      mbid = @mbam.match_artist( ["Jay-Z", "Linkin Park"], "Numb/Encore" )
      mbid.should == 'ae681605-2801-4120-9a48-e18752042306'
      @query.track_queries.should == [["Jay\\-Z and Linkin Park", "Numb/Encore"]]
      @query.artist_queries.should == []
    end
  
    it "should pick out the right artist by name when no track is found" do
      mbid = @mbam.match_artist( "Kate Nash", "Vertigo" )
      mbid.should == '49018fd2-95ef-4f7e-92bb-813159909314'
      @query.track_queries.should == [["Kate Nash", "Vertigo"]]
      @query.artist_queries.should == ["Kate Nash"]
    end

    it "should pick out the right artist by name when no track name for an unambiguous artist" do
      mbid = @mbam.match_artist( "Kate Nash" )
      mbid.should == '49018fd2-95ef-4f7e-92bb-813159909314'
      @query.artist_queries.should == ["Kate Nash"]
    end
    
    it "should pick out the right artist when there are two artists with the same name and track name exists" do
      mbid = @mbam.match_artist( "Oasis", "Wonderwall" )
      mbid.should == '39ab1aed-75e0-4140-bd47-540276886b60'
      @query.track_queries.should == [["Oasis", "Wonderwall"]]
      @query.artist_queries.should == []
    end
    
    
    it "should remove text in brackets from the query title to successfully get a match" do
      mbid = @mbam.match_artist( "Oasis", "Wonderwall (live lounge maida vale session)" )
      mbid.should == '39ab1aed-75e0-4140-bd47-540276886b60'
      @query.track_queries.should == [
        ["Oasis", "Wonderwall \\(live lounge maida vale session\\)"],
        ["Oasis", "Wonderwall"]
      ]
      @query.artist_queries.should == []
    end
    
    it "should fail to find an artist, when there are two artists with the same name and the track isn't found" do
      mbid = @mbam.match_artist( "Oasis", "The Track Does Not Exist" )
      mbid.should be_false
      @query.track_queries.should == [["Oasis", "The Track Does Not Exist"]]
      @query.artist_queries.should == ["Oasis"]
    end
    
    it "should fail to find an artist if there is an artist with an alias of the same name." do
      mbid = @mbam.match_artist( "The Automatic", nil )
      mbid.should == false
      @query.track_queries.should == []
      @query.artist_queries.should == ["The Automatic"]
    end
    
    it "should find an artist which contains 'The ' at the start, when queried without 'The ' at the start, with no track name" do
      mbid = @mbam.match_artist( "Last Shadow Puppets", nil )
      mbid.should == '8a3e1c4f-59a8-457a-826c-fe961419a8ae'
      @query.track_queries.should == []
      @query.artist_queries.should == ["Last Shadow Puppets"]
    end
    
    it "should find an artist which contains 'The ' at the start, when queried without 'The ' at the start, when given a track name" do
      mbid = @mbam.match_artist( "Kooks", "Sofa Song" )
      mbid.should == 'f82f3a3e-29c2-42ca-b589-bc5dc210fa9e'
      @query.track_queries.should == [["Kooks", "Sofa Song"]]
      @query.artist_queries.should == []
    end
    
    it "should find an artist which does not contain 'The ' at the start, when queried with 'The ' at the start" do
      mbid = @mbam.match_artist( "The Delays", "Nearer Than Heaven" )
      mbid.should == 'f86d80f3-3d2e-4450-9b0c-638152e93df3'
      @query.track_queries.should == [["The Delays", "Nearer Than Heaven"]]
      @query.artist_queries.should == []
    end
    
    it "should find an artist which does not contain 'The ' at the start, when queried with 'The ' at the start and it doesn't have an alias" do
      mbid = @mbam.match_artist( "The Brookes Brothers", nil )
      mbid.should == '1ebfdf94-157b-47c0-a71e-9291c6a557cd'
      @query.track_queries.should == []
      @query.artist_queries.should == ['The Brookes Brothers']
    end

    it "should not attempt to match artist names with '**' in their name" do
      @mbam.match_artist('F**k Buttons', 'Bright Tomorrow' ).should be_false
      @query.track_queries.should == []
      @query.artist_queries.should == []
    end

    it "should not attempt to match artist with second artist with '**' in their name" do
      @mbam.match_artist(['Kate Nash', 'F**k Buttons'], 'Pumpkin Soup' ).should be_false
      @query.track_queries.should == []
      @query.artist_queries.should == []
    end
    
    it "should add an entry to the cache when getting a mach just by track" do
      @mbam.match_artist( "Kate Nash", "Pumpkin Soup" )
      @mbam.cache.exist? 'Kate Nash'
      @query.track_queries.should == [["Kate Nash", "Pumpkin Soup"]]
      @query.artist_queries.should == []
    end

    it "should add two entries to the cache when searching for by track and then artist name" do
      @mbam.match_artist( "Kate Nash", "Vertigo" )
      @mbam.cache.exist? 'Kate Nash'
      @mbam.cache.exist? 'Vertigo'
      @query.track_queries.should == [["Kate Nash", "Vertigo"]]
      @query.artist_queries.should == ["Kate Nash"]
    end
    
    it "should cache the response of the first query and not perform a second HTTP GET" do
      @mbam.match_artist( "Kate Nash", "Pumpkin Soup" )
      @mbam.match_artist( "Kate Nash", "Pumpkin Soup" )
      @query.track_queries.should == [["Kate Nash", "Pumpkin Soup"]]
      @query.artist_queries.should == []
    end

    it "should strip whitepsace from the query strings" do
      mbid = @mbam.match_artist( " Kate Nash  ", " Pumpkin Soup " )
      mbid.should == '49018fd2-95ef-4f7e-92bb-813159909314'
      @query.track_queries.should == [["Kate Nash", "Pumpkin Soup"]]
      @query.artist_queries.should == []
    end

    it "should return false if an empty artist name is given" do
      @mbam.match_artist('', nil ).should be_false
      @query.track_queries.should == []
      @query.artist_queries.should == []
    end

    it "should return false if no artist names are given" do
      @mbam.match_artist([], nil ).should be_false
      @query.track_queries.should == []
      @query.artist_queries.should == []
    end

    it "should return false if whitespace artist names are given" do
      @mbam.match_artist([" ", "  ", "    "], "   " ).should be_false
      @query.track_queries.should == []
      @query.artist_queries.should == []
    end
  end
end
