Gem::Specification.new do |s|
  s.name = 'chill'
  s.version = '8.1.0'
  s.summary = "A tiny plug to hook ruby in to couchdb"
  s.email = "a@creativepony.com"
  s.homepage = "http://creativepony.com/chill/"
  s.description = "A little library to talk to a couchdb. I made it skinny, because couchdb is very simple. I think that's a good thing."
  s.author = 'Bluebie'
  s.files = Dir['lib/**.rb'] + ['readme.txt']
  s.require_paths = ['lib']
  
  s.add_dependency 'json', '>= 1.0.0'
  s.add_dependency 'rest-client', '>= 1.6.7'
end