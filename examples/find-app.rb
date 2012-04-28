# Find App is a simple little fulltext search engine, to lookup documents containing words
require '../library/chill.rb'
require 'pp'

ChillDB.goes :FindApp

# delete everything in the database so we have a nice fresh start while experimenting
FindApp.everything.delete!

# a view which will list all the words in our stories
FindApp.design(:search).views(
  # words view splits up all the words then adds them as keys to this document
  words: %q(
    function(doc) {
      if (doc.kind != "story") return;
      var words = doc.text.split(/[^a-z0-9\']+/i);
      for (id in words) {
        emit(words[id].toLowerCase(), {_rev: doc._rev, word: words[id]})
      }
    }
  )
).commit!

# a little template for stories
FindApp.templates(
  story: {
    text: "",
    name: "no name"
  }
)

# add in some stories
FindApp.template(:story).merge(
  name: "Charlotte and the Penguin Exhibit",
  text: %(Charlotte was a computer hacker. Legendary in the scene. She was one of the few people ever to find an SSH vulnerability. Of course, being a girl she was often ignored by the other hackers, which usually worked out to her advantage. And so begins the tale of Charlotte's Big Hack. It was a sunny friday evening in antarctica, where the days are pitch black and the nights are bright as snow. Charlotte was just getting back from a whale riding expedition when she heard the familliar sound of digitized raindrops falling on sheets of glass. Someone was sending her a message!

She ran inside, throwing her big wooly coat away rushing to her computer. Dit dit dit! Each letter suspensfully appeared on her screen. "Wake up neo...". "Blargh" she announced. "This looser keeps bugging me, and I don't even know who this Neo guy is!"

After carefully typing in a sentence so masterfully cutting it best not be repeated, she sighed and flopped back on her fluffy bed with a squeak.
  )
).commit!

FindApp.template(:story).merge(
  name: "The origin of life",
  text: "The cats said let there be life, and so there was life, and it was good."
).commit!

FindApp.template(:story).merge(
  name: "Dearest Fiona",
  text: "Dearest Fiona,

Mary Pebblesworth was an unusual child. Born of parents who fled to Siam, escaping conscription in The Great War. She was never the same after returning. Insisting on eating the most horrifying of foods. Thought to be unwell from the stress of her childhood. Something unusual occurred with this patient. When placed under the care of Sir Pennyworth's Halfway House, it was noted several of her peers began craving and demanding these terrible concoctions just as she had.

At first it was thought there were some terrible joke being played, however it soon became clear we were dealing with the beginnings of a truly terrifying disease on par with childhood legends of African Zombies craving flesh and brain! In a panic Mary was brought by carriage to our estate and provided a room. We were all terribly careful of the risk of infection, and thankfully, we were fine this night.

Two weeks and three days in to my investigation, I foolishly decided on an experiment. I provided the woman with the fishes she had requested, along with exotic beans at no short expense. Carefully observing her 'cooking', so convinced of my immunity to her infectiveity, I witnessed her truly horrifying ritual. Whole fish liquefied before my very eyes, exotic beans ground to a seemingly worthless paste, then set as if by witchcraft in to what I can only describe as cheese. The smells, oh-how they defy words...

We couldn't help ourselves.

I'm terribly sorry.

Yours Faithfully,
Joseph South"
).commit!

# brightens text in terminals which do ANSI codes
def highlight text
  color_code = 7
  "\e[#{color_code}m#{text}\e[0m"
end


# find a story with the word 'it' in it, or a word you specify when calling the program
word = ARGV.first || 'it'
puts "Ran a search for '#{word}':"
it_stories = FindApp.design(:search).query(:words, key: word.downcase, include_docs: true)
it_stories.docs.uniq.each do |story|
  puts "~~~ #{story['name'].upcase} ~~~"
  
  # underline all the search words
  puts story['text'].gsub(Regexp.new("\\b#{Regexp.escape(word)}\\b", 'ig')) { |found| highlight(found) }
  puts "\n\n" # blank lines
end

