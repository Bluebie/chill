# Bluebie's silly little CouchDB abstraction
require 'json' # gem dependancy
require 'rest-client' # gem dependancy
require 'securerandom'
require 'uri'

# The main ChillDB module - This is where it all starts
#
# Throughout these docs you'll find classes under ChillDB. In a real
# application you'll call <tt>ChillDB.goes :SomethingOrOther</tt> and from
# then on, substitute <tt>ChillDB</tt> for <tt>SomethingOrOther</tt> when
# refering to class names. ChillDB effectively creates a copy of itself linked
# to a database called SomethingOrOther on the local couchdb server. Check out
# ChillDB.goes for more details on getting started. Throughout the
# documentation, you'll see KittensApp as a placeholder - imagine
# <tt>ChillDB.goes :KittensApp</tt> has been run beforehand.
module ChillDB
  # Creates a copy of ChillDB linked to a database named with the first
  # argument. You can also provide host, port, user, and pass options as a
  # hash to connect chill to a remote couchdb server or just provide
  # authentication info. Once ChillDB.goes has been called, you'll use the
  # database_name instead of ChillDB when refering to chill's classes
  # throughout your app.
  #
  # Example:
  #   ChillDB.goes :KittensApp
  #   
  #   # load 'frederick' from the KittensApp database
  #   # on the locally installed couch server
  #   KittensApp['frederick'] #=> <ChillDB::Document>
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
  
  # #templates stores a collection of new document templates. This is a handy
  # shortcut to hold your different types of documents. Templates
  # automatically have a property called 'kind' which is assigned to the
  # template's name, which can be handy when writing views. They also provide
  # a great place to write in default values, and are just generally handy as
  # a place to keep a little note to yourself what fields you might expect in
  # a type of document.
  #
  # Example:
  #   KittensApp.templates(
  #     cat: {
  #       color: 'unknown',
  #       softness: 5,
  #       likes: ['exploding', 'cupcakes'],
  #       dislikes: ['dark matter']
  #     }
  #   )
  #   
  #   # use the template, extend it with specific info, and save it!
  #   new_cat = KittensApp.template(:cat).merge(
  #     color: 'octarine',
  #     softness: 13,
  #     _id: 'bjorn'
  #   ).commit!
  def templates obj
    @@templates.merge!(obj) if obj and obj.is_a? Hash
    return @@templates
  end

  # Gets a copy of a template previously defined using #templates. further
  # info on usage is in the description of #templates.
  def template kind
    properties = @@templates[kind.to_sym].dup
    properties[:kind] = kind.to_s
    ChillDB::Document.new(@@database, properties)
  end
  
  # Loads or creates a new ChillDB::Design with a specified name. Designs are
  # used to create views, which create cached high speed document indexes for
  # searching, sorting, and calculating.
  def design name
    ChillDB::Design.new @@database, name
  end

  # Loads or creates a document with a specified _id. If no _id is specified
  # a new blank document is created which will be assigned a fresh UUID as
  # it's _id when saved unless you specify one before committing it.
  #
  # Returns a ChillDB::Document
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
  
  # Commit a ChillDB::Document or a Hash to the database with a specific _id.
  # This method is useful for quickly storing bits of information. For more
  # involved applications, using ChillDB::Document objects directly is
  # best.
  #
  # Returns a copy of the data as a ChillDB::Document, with _rev set to it's
  # new value on the server.
  #
  # Example:
  #   KittensApp['bigglesworth'] = {kind: 'cat', softness: 11}
  def []= document, hash
    raise "Not a hash?" unless hash.is_a? Hash
    hash = hash.dup
    hash['_id'] = document
    return hash.commit! if hash.is_a? ChillDB::Document
    return ChillDB::Document.new(@@database, hash).commit!
  end
  
  # Commit an array of ChillDB::Documents and/or Hashes to the server as new or
  # updated documents. This collection can include ChillDB::Document's marked
  # for deletion, and is the best way to update several documents at the same
  # time. All documents which can be committed will be, and any which cause
  # errors will be reported via a raised ChillDB::BulkUpdateErrors.
  def commit! *documents
    list(documents.flatten).commit!
  end
  
  # A shortcut for #commit! which marks the documents for deletion before
  # applying the commit, effectively bulk deleting them. If any deletions fail
  # a ChillDB::BulkUpdateErrors will be raised with info. All deletions which
  # can succeed, will.
  def delete! *documents
    list(documents.flatten).delete!
  end
  
  # creates a new ChillDB::List from an array of ChillDB::Documents and
  # hashes. This method is mainly used internally for #commit! and #delete!
  # You shouldn't need to use this method.
  def list array = []
    list = ChillDB::List.from_array array
    list.database = @@database
    return list
  end
  
  # Queries the server for every document. Returns a ChillDB::List.
  #
  # This method is mainly useful for maintenence and mockups. Using
  # #everything in production apps is strongly discouraged, as it has severe
  # scalability implications - use a ChillDB::Design view instead if you can.
  # 
  # Example:
  #   # The worst way to look up a document. Never ever do this.
  #   all_of_them = KittensApp.everything # download all documents from server
  #   fredrick = all_of_them['fredrick'] # locally find just the one you want
  #   # Now ruby's garbage collector can happily remove every document you
  #   # ever made from memory. Yay!
  def everything
    list = ChillDB::List.load(JSON.parse(@@database.http('_all_docs?include_docs=true').get.body))
    list.database = @@database
    return list
  end
  
  # Returns this app's ChillDB::Database instance
  def database
    @@database
  end
  
  # Gets a reference to a resource on the database server, useful mainly
  # internally. You shouldn't need to use this method unless using Couch
  # features chill doesn't yet have an interface for.
  def open *args
    headers = { accept: '*/*' }
    headers.merge! args.pop if args.last.respond_to? :to_hash
    @@database.http(args.map { |item| URI.escape(item, /[^a-z0-9_.-]/i) }.join('/'), headers)
  end
end


# A Database abstraction full of internal gizmos and a few external ones too.
# You can access your Database via <tt>KittensApp.database</tt> (following the
# <tt>ChillDB.goes :KittensApp</tt> convention)
#
# The database object is mainly useful for maintenance. The #info method is
# neat for looking up stats on how the database is doing, and you can ask for
# a compaction, to remove old revisions and make database files smaller.
#
# ChillDB::Database is mainly used internally and isn't very useful for most
# chill apps.
class ChillDB::Database
  attr_reader :url, :meta
  
  # Initialize a new database reference. This is used internally by
  # ChillDB.goes, and shouldn't be used directly
  def initialize name, settings = {} # :nodoc:
    @meta = {} # little place to store our things
    @url = URI::HTTP.build(
      host: settings[:host] || 'localhost',
      port: settings[:port] || 5984,
      userinfo: [settings[:user], settings[:pass]],
      path: settings[:path] || "/#{URI.escape hyphenate(name)}/"
    )
    
    # make this database if it doesn't exist yet
    $stderr.puts "New database created at #{@url}" if http('').put('').code == 201
  end
  
  # Ask the CouchDB server to compact this database, effectively making a copy
  # and moving all recent revisions and data across to the new file. You can
  # still keep using your app while a compact is running, and it shouldn't
  # affect performance much. When using CouchDB, compacting is important as
  # Couch databases don't remove any old deleted or updated documents until
  # #compact! is called. This may seem a bit odd, but it is part of how couch
  # can be so reliable and difficult to corrupt during power failures and
  # extended server outages. Don't worry about unless your database files are
  # getting too big.
  #
  # You can check to see if your couch server is currently compacting with
  # the #info method
  def compact!
    request = http('_compact').post('')
    raise request.body unless request.code == 202
    return self
  end
  
  # Gets a Hash of database configuration and status info from the server
  # as a ChillDB::IndifferentHash. This contains all sorts of interesting
  # information useful for maintenance.
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
  
  # grab a RestClient http resource for this database - useful internally
  def http resource, headers = {} # :nodoc:
    RestClient::Resource.new((@url + resource).to_s, headers: {accept: 'application/json', content_type: 'application/json'}.merge(headers)) { |r| r }
  end
  
  private
  
  # a little utility to hyphenate a string
  def hyphenate string
    string.to_s.gsub(/(.)([A-Z])/, '\1-\2').downcase
  end
end








# A simple version of Hash which converts keys to strings - so symbols and
# strings can be used interchangably as keys. Works pretty much like a Hash.
# and also provides method getters and setters via #method_missing
class ChillDB::IndifferentHash < Hash
  def initialize *args # :nodoc:
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
    define_method name do |*args,&proc| # :nodoc:
      super(normalize_hash(args.shift), *args, &proc)
    end
  end
  
  # make hash thing indifferent
  [:has_key?, :include?, :key?, :member?, :delete].each do |name|
    define_method name do |first, *seconds,&proc| # :nodoc:
      first = first.to_s if first.is_a? Symbol
      super(first, *seconds, &proc)
    end
  end
  
  def []= key, value # :nodoc:
    key = key.to_s if key.is_a? Symbol
    super(key, normalize(value))
  end
  
  # Convert to a regular ruby Hash
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








# ChillDB Document, normally created from a template via ChillDB.template or
# from scratch via ChillDB.document or with a specific _id value via
# ChillDB['document-id'] or ChillDB.document('document-id'). Document
# represents a document in your database. It works as a hash with indifferent
# access and method accessors (see also ChillDB::IndifferentHash)
class ChillDB::Document < ChillDB::IndifferentHash
  attr_reader :database
  
  def initialize database, values = false # :nodoc:
    @database = database
    super()
    
    if values.is_a? Symbol
      reset @database.class_variable_get(:@@templates)[values]
    elsif values
      reset values
    end
  end
  
  # replace all values in this document with new ones, effectively making it
  # a new document
  #
  # Arguments:
  #   values: A hash of values
  def reset values
    raise "Argument must be a Hash" unless values.respond_to? :to_hash
    self.replace values.to_hash
    self['_id'] ||= SecureRandom.uuid # generate an _id if we don't have one already
  end
  
  # load a documet from a ChillDB::Database, with a specific document id, and
  # optionally a specific revision.
  #
  # Returns:
  #   New instance of Document
  def self.load database, docid, revision = nil
    new(database, _id: docid).load
  end
  
  # load the current document again from the server, fetching any updates or
  # a specific revision.
  #
  # Returns: self
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
  
  # Write any changes to the database. If this is a new document, one will be
  # created on the Couch server. If this document has a specific _id value it
  # will be created or updated.
  #
  # Returns: self
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
  
  # Mark this document for deletion. A commit! is required to delete the
  # document from the server. You can mark several documents for deletion and
  # supply them to ChillDB.commit! for bulk deletion.
  def delete
    self.replace('_id'=> self['_id'], '_rev'=> self['_rev'], '_deleted'=> true)
  end
  
  # Shortcut for document.delete.commit! - deletes document from server
  # immediately, returning the server's response as a Hash.
  def delete!
    response = @database.http(URI.escape self['_id']).delete()
    response = ChillDB::IndifferentHash.new.replace JSON.parse(response.body)
    raise "Couldn't delete #{self._id}: #{response.error} - #{response.reason}" if response['error']
    delete # make our contents be deleted
    return response
  end
  
  # set the current document revision, reloading document content from the
  # couch server.
  #
  # Arguments:
  #   new_revision: (String)
  def revision= new_revision
    load new_revision
  end
  
  # get's the current document revision identifier string
  #
  # Returns: (String) revision identifier
  def revision
    self['_rev']
  end
  
  # fetch an array of this document's available revisions from the server
  #
  # Returns: array of revision identifier strings
  def revisions
    request = @database.http("#{URI.escape self['_id']}?revs=true").get
    json = JSON.parse(request.body)
    json['_revisions']['ids']
  end
  
  # to_param is supplied for integration with url routers in web frameworks
  # like Rails and Camping. Defaults to returning the document's _id. You can
  # just pass documents in to functions which generate urls in your views in
  # many ruby frameworks, and it will be understood as the _id of the document
  #
  # If you have a more intelligent behaviour, monkeypatch in some special
  # behaviour.
  #
  # Returns:
  #   (String): self['_id']
  def to_param
    self['_id']
  end
  
  # A loose equality check. Two documents are considered equal if their _id
  # and _rev are equal, and they are both of the same class. This is handy
  # when dealing with Array's and ChillDB::List's. For instance, you may want
  # to query one view, then remove the values found in another view
  #
  # Example:
  #
  #   kittens = KittensApp.design(:lists).query(:cats)
  #   kittens -= KittensApp.design(:lists).query(:adults)
  #   # kittens now contains cats who are not adults
  #
  # Of course if you're doing this sort of thing often, you really should
  # consider precomputing it in a view.
  def == other_doc
    (other.class == self.class) and (self['_id'] == other['_id']) and (self['_rev'] == other['_rev'])
  end
end





# A special sort of Array designed for storing lists of documents, and
# particularly the results of ChillDB::Design#query. It works sort of like a
# hash, in supporting lookups by key, and sort of like an array, in its sorted
# nature. It keeps the association of keys, documents, values, id's, and also
# provides a simple way to bulk commit all the documents in the list or delete
# all of them form the server in one efficient request.
#
# The recomended way to create a list from a regular array is ChillDB.list()
# as some of List's functionality depends on it having a link to the database.
class ChillDB::List < Array
  attr_accessor :total_rows, :offset, :database
  
  # creates a new List from a couchdb response
  def self.load list, extras = {} # :nodoc:
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
  def self.from_array array # :nodoc:
    new_list = self.new
    new_list.replace array.map do |item|
      { 'id'=> item['_id'], 'key'=> item['_id'], 'value'=> item, 'doc'=> item }
    end
  end
  
  # store rows nicely in mah belleh
  def rows=(arr) # :nodoc:
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
  
  # Grab all the rows - actually just self.
  def rows
    self
  end
  
  # Returns an Array of all the document _id strings in the list
  def ids
    self.map { |i| i['id'] }
  end
  
  # Returns an Array of keys in the list
  def keys
    self.map { |i| i['key'] }
  end
  
  # Returns an Array of all the emitted values in the list
  def values
    self.map { |i| i['value'] }
  end
  
  # Returns an Array of all the documents in this list.
  #
  # Note that querying a view with ChillDB::Design#query does not include
  # documents by default. Calling ChillDB::Design#query with the include_docs
  # option set to true causes the database to lookup all of the documents.
  def docs
    self.map { |i| i['doc']  }
  end
  
  # Iterates each key/value pair using a supplied proc.
  #
  # Example: 
  #
  #   list.each_pair do |key, value|
  #     puts "#{key}: #{value.inspect}"
  #   end
  #
  # :yeild: key, value
  def each_pair &proc
    self.each { |item| proc.call(item['key'], item['value']) }
  end
  
  # fetch a document by it's id from this list. Useful only for queries with
  # <pp>{ include_docs: true }</pp> set
  def id value
    self.find { |i| i['id'] == value }['doc']
  end
  
  # Lookup a key from the list. Returns a ChillDB::IndifferentHash containing:
  #
  #   {
  #     'key'   => key from database
  #     'value' => emitted value in view, if any
  #     'doc'   => document, if view queried with { include_docs: true }
  #     'id'    => id of document which emitted this result
  #   }
  def key value
    ChillDB::IndifferentHash.new.replace(self.find { |i| i['key'] == value })
  end
  
  # Lookup a document, by a key in the list. If there are multiple entries
  # in the view with this key, the first document is returned.
  #
  # Note this will return nil for lists returned by ChillDB::Design#query
  # unless the query was done with the include_docs option set to true.
  def [] key
    return key(key)['doc'] unless key.respond_to? :to_int
    super
  end
  
  # make a regular ruby hash version
  #
  # By default returns a hash containing <tt>{ key: value }</tt> pairs from
  # the list. Passing :doc as the optional argument instead creates a hash of
  # <tt>{ key: doc }</tt> pairs.
  def to_h value = :value
    hash = ChillDB::IndifferentHash.new
    
    each do |item|
      hash[item['key']] = item[value.to_s]
    end
    
    return hash
  end
  
  # Commit every document in this list to the server in a single quick
  # request. Every document which can be committed will be, and if any fail
  # a ChillDB::BulkUpdateErrors will be raised.
  #
  # Returns self. 
  def commit!
    commit_documents! convert
  end
  alias_method :commit_all!, :commit!
  
  # Delete every document in this list from the server. If this list was
  # returned by ChillDB::Design#query, your view's values will need to be a
  # Hash containing <tt>rev</tt> or <tt>_rev</tt> - indicating the document's
  # revision. You can also query your view with <tt>{ include_docs: true }</tt>
  # specified as an option. Deletion cannot happen without a revision
  # identifier. All documents which can be deleted, will be. If there are any
  # errors, they'll be raised as a ChillDB::BulkUpdateErrors.
  #
  # Returns self.
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






# Representing a named design in the Couch database, Design is used to setup
# views. Views index all of the documents in your database, creating
# ChillDB::List's for each emitted document. Your views can choose to emit
# as many entries as you like for each document, or none at all. Views can be
# as simple as listing all of a certain kind of document, or more complex
# schemes like extracting every word in a document and generating an index of
# words in documents for a simple but powerful search engine.
#
# For more information on designs and views, CouchDB: The Definitive Guide is
# a great resource. http://guide.couchdb.org/draft/design.html
#
# Example:
#   KittensApp.design(:lists).views(
#     # lists all cats with a softness rating of two or more
#     soft_cats: 'function(doc) {
#       if (doc.kind == "cat" && doc.softness > 1) emit(doc._id, null);
#     }'
#   ).commit!
# 
# Note that views default to being javascript functions, as this is what couch
# ships with support for. It is possible to 
class ChillDB::Design
  attr_accessor :name
  
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
  
  # Add more views to an existing design. See also #views
  def add_views collection
    document['views'].merge! views_preprocess(collection)
    return self
  end
  
  # Set the views in this design. Argument is a Hash containing String's for
  # each javascript (by default) view function. Reduce functions can also be
  # included optionally.
  # 
  # Example:
  #   KittensApp.design(:lists).views(
  #     # just a map function
  #     adults: 'function(doc) {
  #       if (doc.kind == "cat" && doc.age > 4) emit(doc._id, null);
  #     }',
  #   
  #     # a map and a reduce - lookup the overall softness of our kitten database
  #     # when queried returns just one value: the number output of the reduce
  #     # function.
  #     softness: {
  #       map: 'function(doc) {
  #         if (doc.kind == "cat") emit(doc._id, doc.softness);
  #       }',
  #       reduce: 'function(key, values, rereduce) {
  #         return sum(values); // add them all together
  #       }'
  #     }
  #   ).commit!
  # 
  #   KittensApp.design(:lists).query(:adults) #=> <ChillDB::List> [a, b, c...]
  #   KittensApp.design(:lists).query(:softness) #=> 19
  #
  # Check out http://wiki.apache.org/couchdb/Introduction_to_CouchDB_views for
  # a great introduction to CouchDB view design.
  def views collection
    document['views'] = {}
    add_views collection
    return self
  end
  
  # get's the current language of this design document. Usually this would be
  # "javascript". If called with an argument, set's the language property and
  # returns self.
  #
  # Example:
  #   KittensApp.design(:lists).language #=> "javascript"
  #   KittensApp.design(:lists).language(:ruby) #=> KittensApp.design(:lists)
  #   KittensApp.design(:lists).language #=> "ruby"
  # 
  #   # chain it together with views for extra nyan:
  #   KittensApp.design(:lists).language(:ruby).views(
  #     soft_cats: %q{ proc do |doc|
  #       emit doc['_id'], doc['softness'] if doc['softness'] > 1 
  #     end }
  #   )
  #
  # ChillDB doesn't currently include a ruby view server, and it needs to be
  # specifically configured and installed before you can use one. More info
  # in an implementation is at http://theexciter.com/articles/couchdb-views-in-ruby-instead-of-javascript.html
  def language set = nil
    if set
      @document['language'] = set.to_s
      self
    else
      @document['language']
    end
  end
  
  # Commit this design document to the server and start the server's process
  # of updating the view's contents. Note that querying the view immediately
  # after a commit may be slow, while the server finishes initially processing
  # it's contents. The more documents you have, the more time this can take.
  def commit!
    document['_id'] = "_design/#{@name}"
    document.commit!
  end
  
  # Query a named view. Returns a ChillDB::List, which works like a Hash or an
  # Array containing each result. Optionally pass in arguments. Check out
  # http://wiki.apache.org/couchdb/HTTP_view_API#Querying_Options for the
  # definitive list. Some really useful options:
  #
  # Options:
  #   include_docs: (true or false) load documents which emitted each entry?
  #   key: only return items emitted with this exact key
  #   keys: (Array) only return items emitted with a key in this Array
  #   range: (Range) shortcut for startkey, endkey, and inclusive_end
  #   startkey: return items starting with this key
  #   endkey: return items ending with this key
  #   startkey_docid: (String) return items starting with this document id
  #   endkey_docid: (String) return items ending with this document id
  #   inclusive_end: (true or false) defaults true, endkey included in result?
  #   limit: (Number) of documents to load before stopping
  #   stale: (String) 'ok' or 'update_after' - view need not be up to date.
  #   descending: (true or false) direction of search?
  #   skip: (Number) skip the first few documents - slow - not recomended!
  #   group: (true or false) should reduce grouping by exact identical key?
  #   group_level: (Number) first x items in key Array are used to group rows
  #   reduce: (true or false) should the reduce function be used?
  #   update_seq: (true or false) response includes sequence id of database?
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
  
  # handles the little shortcut for specifying only a map function
  def views_preprocess views_hash
    views_hash.each do |key, value|
      views_hash[key] = { map: value } if value.respond_to? :to_str
    end
    return views_hash
  end
end




# Represents one or more failure when doing a bulk commit or delete.
class ChillDB::BulkUpdateErrors < StandardError
  # Array of failure messages
  attr_accessor :failures
  
  def initialize *args # :nodoc:
    @failures = args.pop
    super(*args)
  end
  
  # friendly message listing the failures for each document
  def inspect
    "<ChillDB::BulkUpdateError>:\n" + @failures.map { |failure|
      document, error = failure
      "  '#{document['_id']}' => #{error['reason']}"
    }.join('\n')
  end
end



