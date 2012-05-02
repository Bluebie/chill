require '../lib/chill.rb'
# A simple test to check the new bulk commit api works as intended
# by Bluebie

ChillDB.goes :BulkBag

BulkBag.everything.delete! # clear out our test database

BulkBag.commit!(
  { _id: 'brother1', name: "Lucky" },
  { _id: 'brother2', name: "Fyr" }
);

raise "fail" unless BulkBag['brother1'].name == 'Lucky'
raise "fail" unless BulkBag['brother2'].name == 'Fyr'

puts "Success! Brother1's name is #{ BulkBag['brother1'].name }"