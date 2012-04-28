.oOo. .oOo. .oOo. chill .oOo. .oOo. .oOo.

chill plugs ruby code in to CouchDB


~~~ USAGE ~~~
require 'pp'
require 'chill'

# make a database or connect to one
ChillDB.goes :KittensApp

# add a template (just in ruby instance)
KittensApp.templates(
  cat: {
    color: 'invisible',
    softness: 5,
    likes: %w{water food flying spaceships sunlight tictacs hugs exploding},
    dislikes: %w{mysql}
  }
)

# get a copy of a template, change some things, and save it
KittensApp.template(:cat).merge(
  color: 'green',
  softness: 8,
  dislikes: %w{stylesheets},
  _id: 'fredrick'
)

# add a view
KittensApp.design(:lists).views(
  soft_cats: 'function(doc) {
    if (doc.kind == "cat" && doc.softness > 1) emit(doc._id, null);
  }'
).commit!

# add a kitten
KittensApp.template(:cat).merge(_id: 'fredrick', softness: 16, dislikes: ['silly business']).commit!

# use the view to get a list of non-hard cats
soft_ones = KittensApp.design(:lists).query(:soft_cats)
soft_ones.each do |cat|
  pp cat
end

# just load fredrick
fredrick = KittensApp['fredrick']


~~~ MORE INFORMATION THAN YOU REQUIRE ~~~
You can see a more fully baked version of the KittensApp database in examples/kittens-app.rb. There you will see how to do all sorts of things. It's the start of a really great kitten database you could use to keep track of your cats. It's web scale and cloud ready.

