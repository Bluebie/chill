Gem::Specification.new do |s|
  s.name = 'chill'
  s.version = '2'
  s.require_path = '.'
  s.summary = "A tiny plug to hook ruby in to couchdb"
  s.email = "a@creativepony.com"
  s.homepage = "http://github.com/Bluebie/chill"
  s.description = "A little library to talk to a couchdb. I made it skinny, because couchdb is very simple. I think that's a good thing."
  s.author = 'Bluebie'
  s.files = Dir['library/**.rb']
  #s.test_file = 'test.rb'
  s.add_dependency 'json', '>= 1.6.0'
  s.add_dependency 'rest-client', '>= 1.6.7'
  s.add_dependency 'uuid', '>= 2.3.4'
end