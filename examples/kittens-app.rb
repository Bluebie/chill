require '../lib/chill.rb'
require 'pp'

# make a database or connect to one
ChillDB.goes :KittensApp

# delete everything and start fresh
KittensApp.everything.delete!

# add a template (just in ruby instance)
KittensApp.templates(
  cat: {
    color: 'invisible',
    softness: 5,
    likes: %w{water food flying spaceships sunlight tictacs hugs exploding},
    dislikes: %w{mysql}
  }
)

# add a view
KittensApp.design(:lists).views(
  soft_cats: 'function(doc) {
    if (doc.kind == "cat" && doc.softness > 1) emit(doc._id, null);
  }'
).commit!

# add kittens
KittensApp.template(:cat).merge(_id: 'fredrick', softness: 16, dislikes: ['silly business']).commit!
KittensApp.template(:cat).merge(_id: 'bobby', softness: 2, dislikes: ['mice']).commit!
KittensApp.template(:cat).merge(_id: 'cheezly', softness: 1, dislikes: ['soy cheese products']).commit!

# use the view to get a list of non-hard cats
puts "Kitten Database lookup - soft cats:"
soft_ones = KittensApp.design(:lists).query(:soft_cats, include_docs: true)
soft_ones.docs.each do |cat|
  puts "#{cat['_id']} is #{cat['softness']} soft"
end

# just load fredrick
fredrick = KittensApp['fredrick']
puts "Fredrick's stats:"
fredrick.each do |item, value|
  puts "#{item.rjust(10)}- #{value}"
end

# get the nonsoft cats the slow way - in ruby instead of with a view
nonsofties = (KittensApp.everything.docs - soft_ones.docs).select { |i| i['kind'] == 'cat' }
puts "Nonsoft cats: #{nonsofties.map { |cat| cat['_id'] }.join(', ')}"
