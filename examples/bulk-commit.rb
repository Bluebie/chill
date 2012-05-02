require '../lib/chill.rb'
# A simple test to check the new bulk commit api works as intended
# by Bluebie

ChillDB.goes :BulkBag

BulkBag.delete! BulkBag.everything # clear out our test database, using new bulk delete api

BulkBag.commit!(
  { _id: 'brother1', name: "Lucky" },
  { _id: 'brother2', name: "Fyr" }
);

raise "fail" unless BulkBag['brother1'].name == 'Lucky'
raise "fail" unless BulkBag['brother2'].name == 'Fyr'

puts "Success! Brother1's name is #{ BulkBag['brother1'].name }"