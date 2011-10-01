.oOo. .oOo. .oOo. chill .oOo. .oOo. .oOo.

chill plugs ruby code in to CouchDB


~~~ USAGE ~~~

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
).commit!

# add a view
KittensApp.design(:lists).views(
  soft_cats: 'function(doc) {
    if (doc.kind == "cat" && softness > 1) emit(doc._id, null);
  }'
).commit!

# use the view to get a list of non-hard cats
soft_ones = KittensApp.design(:lists).query(:soft_cats)
soft_ones.each do |cat|
  pp cat
end

# just load fredrick
fredrick = KittensApp['fredrick']

