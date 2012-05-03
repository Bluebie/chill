require '../lib/chill'
require 'benchmark'
# A little benchmark to illustrate the performance difference between a bulk commit and individual commits
ChillDB.goes :BulkCommitBenchmark
Documents = 1000 # benchmark 1000 documents

puts "Bulk Commit of #{Documents}"
puts Benchmark.realtime {
  BulkCommitBenchmark.commit! Documents.times.map { { random_number: rand(50) } }
}

puts "Single Commit of #{Documents}"
puts Benchmark.realtime {
  Documents.times do 
    { random_number: rand(50) }
    BulkCommitBenchmark.document( random_number: rand(50) ).commit! 
  end
}
