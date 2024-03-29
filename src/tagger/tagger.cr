require "./taggers/*"
require "../models/tagger"

macro define_taggers(*taggers)
  {% for tagger in taggers %}
    instance = {{tagger}}.new(options)
    tagger_list << instance
  {% end %}
end

module NoirTaggers
  HasTaggers = {
    :hunt => {
      :name  => "HuntParam Tagger",
      :desc  => "Identifies common parameters vulnerable to certain vulnerability classes",
      :class => HuntParamTagger,
    },
  }

  def self.get_taggers
    HasTaggers
  end

  def self.run_tagger(endpoints : Array(Endpoint), options : Hash(Symbol, String), use_taggers : String)
    tagger_list = [] of Tagger # This will hold instances of taggers

    # Define taggers by creating instances
    # Assuming HuntParamTagger is defined and is the only tagger
    define_taggers(HuntParamTagger)

    # Parsing use_taggers
    use_taggers_arr = use_taggers.split(",")
    use_taggers_arr = use_taggers_arr.map(&.strip)

    # Run taggers
    tagger_list.each do |tagger|
      tagger.perform(endpoints) if use_taggers_arr.includes?(tagger.name) || use_taggers_arr.includes?("all")
    end
  end
end
