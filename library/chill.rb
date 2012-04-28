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
    if id.respond_to? :to_ary
      list = id.to_ary.map { |i| i.to_s }
      response = @@database.http('_all_docs?include_docs=true').post({ keys: list }.to_json)
      ChillDB::List.load(JSON.parse(response), database: @@database)
    elsif id.respond_to? :to_str
      ChillDB::Document.load(@@database, id.to_str)
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
  
  # commit takes an array of documents, and does a bulk commit to the server (one single request)
  # using a bulk commit is faster than calling commit! on each individual document object
  def commit! *args
    list(args.flatten).commit!
  end
  
  def delete! *args
    list(args.flatten).delete!
  end
  
  # turn an array of documents in to a ChillDB::List
  def list array = []
    list = ChillDB::List.from_array array
    list.database = @@database
    return list
  end
  
  # all docs!
  def everything
    list = ChillDB::List.load(JSON.parse(@@database.http('_all_docs?include_docs=true').get.body))
    list.database = @@database
    return list
  end
  
  # open a resource to the server for a particular document, which you can get, post, etc to. For internal use.
  def open *args
    headers = { accept: '*/*' }
    headers.merge! args.pop if args.last.respond_to? :to_hash
    @@database.http(args.map { |item| URI.escape(item, /[^a-z0-9_.-]/i) }.join('/'), headers)
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
  
  # get info about database
  def info
    response = http('').get()
    IndifferentHash.new.replace(JSON.parse response.body)
  end
  
  # pretty output for debugging things :)
  def inspect
    "#<ChillDB::Database: #{info.inspect} >"
  end
  
  #def revs_limit; http('_revs_limit').get.body.to_i; end
  #def revs_limit=(v); http('_revs_limit').put(v.to_s); end
  
  # grab a RestClient http resource for this database
  def http resource, headers = {}
    RestClient::Resource.new((@url + resource).to_s, headers: {accept: 'application/json', content_type: 'application/json'}.merge(headers)) { |r| r }
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
    return self[name.to_s] if self.key? name.to_s
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
    return ChillDB::IndifferentHash.new.replace(thing) if thing.respond_to? :to_hash unless thing.is_a? self.class
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
    lookup_revision ||= self['_rev']
    url.query = "rev=#{lookup_revision}" if lookup_revision
    response = @database.http(url).get
    return self if response.code == 404 # we can create it later
    raise response.body if response.code != 200
    
    reset JSON.parse(response.body)
    return self
  end
  
  # stores updates (or newly existingness) of document to origin database
  def commit!
    return delete! if self['_deleted'] # just delete if we're marked for deletion
    json = JSON.generate(self)
    response = @database.http(URI.escape self['_id']).put(json);
    raise response.body unless (200..299).include? response.code
    json = JSON.parse(response.body)
    raise "Not ok! #{response.body}" unless json['ok']
    self['_id'] = json['id']
    self['_rev'] = json['rev']
    return self
  end
  
  # mark this jerk for deletion! (useful for bulk commit)
  def delete
    self.replace('_id'=> self['_id'], '_rev'=> self['_rev'], '_deleted'=> true)
  end
  
  # delete this jerk immediately
  def delete!
    response = @database.http(URI.escape self['_id']).delete()
    response = ChillDB::IndifferentHash.new.replace JSON.parse(response.body)
    raise "Couldn't delete #{self._id}: #{response.error} - #{response.reason}" if response['error']
    delete # make our contents be deleted
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
  
  # for integration with url routers in webapps, to_param defaults to _id - which you can use straight up in urls
  def to_param
    self['_id']
  end
  
  # loose equality check
  def == other_doc
    other.is_a?(self.class) and (self['_id'] == other['_id']) and (self['_rev'] == other['_rev'])
  end
end






class ChillDB::List < Array
  attr_accessor :total_rows, :offset, :database
  
  # creates a new List from a couchdb response
  def self.load list, extras = {}
    new_list = self.new
    
    raise "#{list['error']} - #{list['reason']}" if list['error']
    [extras, list].each do |properties|
      properties.each do |key, value|
        new_list.send("#{key}=", value)
      end
    end
    
    return new_list
  end
  
  # to make a list from a simple array (not a couchdb response...)
  def self.from_array array
    new_list = self.new
    new_list.replace array.map do |item|
      { 'id'=> item['_id'], 'key'=> item['_id'], 'value'=> item, 'doc'=> item }
    end
  end
  
  # store rows nicely in mah belleh
  def rows=(arr)
    self.replace(arr.map { |item|
      if item['value'].is_a? Hash
        if item['value'].respond_to?(:[]) && item['value']['_id']
          item['value']['_id'] ||= item['id']
          item['value'] = ChillDB::Document.new(@database, item['value'])
        else
          item['value'] = ChillDB::IndifferentHash.new.replace(item['value'])
        end
      end
      
      item['doc'] = ChillDB::Document.new(@database, item['doc']) if item['doc']
      
      item
    })
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
    self.map { |i| i['doc']  }
  end
  
  def each_pair &proc
    self.each { |item| proc.call(item['key'], item['value']) }
  end
  
  # gets an item by id value
  def id value
    self.find { |i| i['id'] == value }['doc']
  end
  
  def key value
    self.find { |i| i['key'] == value }
  end
  
  def [] key
    return key(key)['doc'] unless key.respond_to? :to_int
    super
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
  
  # commit takes an array of documents, and does a bulk commit to the server (one single request)
  # using a bulk commit is faster than calling commit! on each individual document object
  def commit!
    commit_documents! convert
  end
  alias_method :commit_all!, :commit!
  
  # remove all the documents in this list from the database
  def delete!
    # check all the entries have a _rev - if they don't they cannot be deleted!
    each do |item|
      rev = item['value']['_rev'] || item['value']['rev'] || item['doc']['_rev']
      raise "Some (all?) items in list do not contain _rev properties in their values" unless rev
    end
    
    # mark all documents for deletion and commit the order!
    commit_documents! convert.map { |item| item.delete }
  end
  
  alias_method :delete_all!, :delete!
  
  private
  # get the list, with any non-ChillDB::Document's converted in to those
  def convert
    map do |item|
      document = item['doc'] || item['value']
      if document.is_a? ChillDB::Document
        document
      elsif document.respond_to? :to_hash
        document['_rev'] ||= item['value']['_rev'] || item['value']['rev'] || item['doc']['_rev']
        document = ChillDB::Document.new(@database, document.to_hash)
      else
        raise "Cannot convert #{document.inspect}"
      end
    end
  end
  
  # commit an array of documents to the server
  def commit_documents! documents
    response = @database.http('_bulk_docs').post(JSON.generate(docs: documents.to_a))
    raise response.body unless (200..299).include? response.code
    json = JSON.parse(response.body)
    errors = []
    
    documents.each_index do |index|
      self[index]['id'] = json[index]['id']
      self[index]['value']['rev'] = json[index]['rev'] if json[index]['rev']
      errors.push [self[index], json[index]] if json[index]['error']
    end
    
    raise errors unless errors.empty?
    return self
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
    
    # put the results in to a QueryResults object - a glorified array
    return ChillDB::List.load(JSON.parse(response.body), database: @database)
  end
  
  private
  
  def views_preprocess views_hash
    views_hash.each do |key, value|
      views_hash[key] = { map: value } if value.respond_to? :to_str
    end
    return views_hash
  end
end





class ChillDB::BulkUpdateErrors < StandardError
  attr_accessor :failures
  
  def initialize *args
    @failures = args.pop
    super(*args)
  end
  
  def inspect
    "ChillDB::BulkUpdateError:\n" + @failures.map { |failure|
      document, error = failure
      "  '#{document['_id']}': #{error['reason']}"
    }.join('\n')
  end
end



