# Bluebie's silly little CouchDB abstraction
require 'json'
require 'uuid'
require 'rest-client'
require 'uri'

module ChillDB
  def self.goes database_name, *args
    submod = Module.new do
      extend ChillDB
      @@database = ChillDB::Database.new database_name, *args
      @@templates = {}
    end
    self.constants(false).each do |const|
      submod.const_set(const, self.const_get(const));
    end
    Object.const_set(database_name, submod)
  end
  
  # stores a list of templates which can be used to make a new document
  def templates obj
    @@templates.merge!(obj) if obj and obj.is_a? Hash
    return @@templates
  end

  # get a new document consisting of a template
  def template kind
    properties = @@templates[kind].dup
    properties[:kind] = kind.to_s
    ChillDB::Document.new(@@database, properties)
  end
  
  # get a design with a particular name - or make one!
  def design name
    ChillDB::Design.new @@database, name
  end

  # get or make a document with a particular id/name, or just a blank new one
  def document id = false
    if id
      ChillDB::Document.load(@@database, id)
    else
      ChillDB::Document.new(@@database)
    end
  end
  alias_method :[], :document
  
  def []= document, hash
    raise "Not a hash?" unless hash.is_a? Hash
    hash = hash.dup
    hash['_id'] = document
    return hash.commit! if hash.is_a? ChillDB::Document
    return ChillDB::Document.new(@@database, hash).commit!
  end
end

class ChillDB::Database
  attr_reader :url, :meta
  def initialize name, settings = {}
    @meta = {} # little place to store our things
    @url = URI::HTTP.build(
      host: settings[:host] || 'localhost',
      port: settings[:port] || 5984,
      userinfo: [settings[:user], settings[:pass]],
      path: "/#{URI.escape hyphenate(name)}/"
    )
    
    # make this database if it doesn't exist yet
    $stderr.puts "New database created at #{@url}" if http('').put('').code == 201
  end
  
  # ask the server to compact this database
  def compact!
    request = http('_compact').post('')
    raise request.body unless request.code == 202
    return self
  end
  
  #def revs_limit; http('_revs_limit').get.body.to_i; end
  #def revs_limit=(v); http('_revs_limit').put(v.to_s); end
  
  # grab a RestClient http resource for this database
  def http resource
    RestClient::Resource.new((@url + resource).to_s, :headers => {accept: 'application/json', content_type: 'application/json'}) { |r| r }
  end
  
  private
  
  # a little utility to hyphenate a string
  def hyphenate string
    string.to_s.gsub(/(.)([A-Z])/, '\1-\2').downcase
  end
end









# handles conversion of symbol keys to strings, and method accessors
class ChillDB::IndifferentHash < Hash
  def initialize *args
    super(*args) do |hash, key| # indifferent access
      hash[key.to_s] if Symbol === key
    end
  end
  
  # getters and setters for hash items
  def method_missing name, *args
    return self[name.to_s] if self[name.to_s]
    return self[name.to_s[0...-1]] = args.first if name.to_s.end_with? '=' and args.length == 1
    super
  end
  
  # make hash thing indifferent
  [:merge, :merge!, :replace, :update, :update!].each do |name|
    define_method name do |*args,&proc|
      super(normalize_hash(args.shift), *args, &proc)
    end
  end
  
  # make hash thing indifferent
  [:has_key?, :include?, :key?, :member?, :delete].each do |name|
    define_method name do |first, *seconds,&proc|
      first = first.to_s if first.is_a? Symbol
      super(first, *seconds, &proc)
    end
  end
  
  def []= key, value
    key = key.to_s if key.is_a? Symbol
    super(key, normalize(value))
  end
  
  # return an actual hash
  def to_hash
    Hash.new.replace self
  end
  
  
  private
  # normalises all symbols in a hash in to string keys
  def normalize_hash original_hash
    hash = {}
    original_hash.each do |key,value|
      key = key.to_s if key.is_a? Symbol
      hash[key] = normalize value
    end
    return hash
  end
  
  def normalize thing
    return ChillDB::IndifferentHash.new.replace(thing) if thing.is_a? Hash
    return thing.map { |i| normalize(i) } if thing.is_a? Array
    return thing;
  end
end









class ChillDB::Document < ChillDB::IndifferentHash
  attr_reader :database
  
  def initialize database, values = false
    @database = database
    super()
    
    if values.is_a? Symbol
      reset @database.class_variable_get(:@@templates)[values]
    elsif values
      reset values
    end
  end
  
  def reset values
    self.replace values
    self['_id'] ||= UUID.new.generate # generate an _id if we don't have one already
  end
  
  def self.load database, docid
    new(database, _id: docid).load
  end
  
  # load this document from server in to this local cache
  # returns self, or if there's a more specific subclass, a subclassed version of Document
  def load lookup_revision = nil
    url = URI(URI.escape self['_id'])
    url.query = "rev=#{lookup_revision}" if lookup_revision
    response = @database.http(url).get
    return self if response.code == 404 # we can create it later
    raise response.body if response.code != 200
    
    reset JSON.parse(response.body)
    return self
  end
  
  # stores updates (or newly existingness) of document to origin database
  def commit!
    json = JSON.generate(self)
    response = @database.http(URI.escape self['_id']).put(json);
    raise response.body unless (200..299).include? response.code
    json = JSON.parse(response.body)
    raise "Not ok! #{response.body}" unless json['ok']
    self['_id'] = json['id']
    self['_rev'] = json['rev']
    return self
  end
  
  # delete this jerk
  def delete!
    response = @database.http(URI.escape self['_id']).delete()
    response = ChillDB::IndifferentHash.new.replace JSON.parse(response.body)
    raise "Couldn't delete #{self._id}: #{response.error} - #{response.reason}" if response['error']
    return response
  end
  
  # set current revision to a different thing
  def revision= new_revision
    load new_revision
  end
  
  # gets a list of revisions
  def revisions
    request = @database.http("#{URI.escape self['_id']}?revs=true").get
    json = JSON.parse(request.body)
    json['_revisions']['ids']
  end
end






class ChillDB::List < Array
  attr_accessor :total_rows, :offset, :database
  
  # store rows nicely in mah belleh
  def rows=(arr)
    self.replace arr.map { |item| ChillDB::IndifferentHash.new.replace(item) }
  end
  
  # we are the rows!
  def rows
    self
  end
  
  def ids
    self.map { |i| i['id'] }
  end
  
  def keys
    self.map { |i| i['key'] }
  end
  
  def values
    self.map { |i| i['value'] }
  end
  
  def docs
    self.map { |i| i['doc'] }
  end
  
  def each_pair &proc
    self.each { |item| proc.call(item['key'], item['value']) }
  end
  
  # make a regular ruby hash version
  # if you want docs as values instead of emitted values, use to_h(:doc)
  def to_h value = :value
    hash = ChillDB::IndifferentHash.new
    
    each do |item|
      hash[item['key']] = item[value.to_s]
    end
    
    return hash
  end
  alias_method :to_hash, :to_h
  
  # remove all the documents in this list from the database
  def delete_all!
    each { |item|
      raise "Not all documents listed are emitted as values in this view" if item.id != item.value._id
    }
    
    request = { docs: map { |item|
      { _id: item.value._id, _rev: item.value._rev, _deleted: true }
    } }
    
    response = JSON.parse @database.http("_bulk_docs").post(request.to_json)
    raise "Error: #{response['error']} - #{response['reason']}" if response.is_a? Hash and response['error']
    
    return ChillDB::IndifferentHash.new.replace response
  end
end







class ChillDB::Design
  attr_accessor :name # can rename with that - though leaves old copy on server probably
  
  def initialize database, name
    @database = database
    @name = name.to_s
  end
  
  # lazy load document - referencing this causes load from database
  def document
    @document ||= ChillDB::Document::load @database, "_design/#{@name}"
    @document['language'] ||= 'javascript'
    @document['views'] ||= {}
    return @document
  end
  
  # adds views
  def add_views collection
    document['views'].merge! views_preprocess(collection)
    return self
  end
  
  # sets views
  def views collection
    document['views'] = {}
    add_views collection
    return self
  end
  
  # store changes to server
  def commit!
    document['_id'] = "_design/#{@name}"
    document.commit!
  end
  
  # query a view - response is an array augmented with methods like arr.total_rows
  def query view, options = {}
    if options[:range]
      range = options.delete[:range]
      options[:startkey], options[:endkey] = range.first, range.last
      options[:startkey], options[:endkey] = options[:endkey], options[:startkey] if options[:descending]
      options[:inclusive_end] = !range.exclude_end?
    end
    
    # these options need to be json encoded
    [:key, :startkey, :endkey, :keys, :descending, :limit, :skip, :group, :group_level,
     :reduce, :include_docs, :inclusive_end, :update_seq
    ].each do |name|
      options[name] = options[name].to_json if options.has_key? name
    end
    
    opts = options.map { |key, value| "#{URI.escape(key.to_s)}=#{URI.escape(value.to_s)}" }.join('&')
    url = "_design/#{URI.escape @name}/_view/#{URI.escape view.to_s}?#{opts}"
    response = @database.http(url).get()
    json = JSON.parse response.body
    raise "#{json['error']} - #{json['reason']} @ #{url}" if json['error']

    # put the results in to a QueryResults object - a glorified array
    results = ChillDB::List.new
    results.database = @database
    json.each do |key, value|
      results.send("#{key}=", value)
    end
    
    return results
  end
  
  private
  
  def views_preprocess views_hash
    views_hash.each do |key, value|
      views_hash[key] = { map: value } if value.respond_to? :to_str
    end
    return views_hash
  end
end




