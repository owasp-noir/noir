require "./taggers/*"
require "../models/tagger"

module NoirTaggers
  HasTaggers = {
    hunt: {
      name:   "HuntParam Tagger",
      desc:   "Identifies common parameters vulnerable to certain vulnerability classes",
      runner: HuntParamTagger,
    },
    oauth: {
      name:   "OAuth Tagger",
      desc:   "Identifies OAuth endpoints",
      runner: OAuthTagger,
    },
    cors: {
      name:   "CORS Tagger",
      desc:   "Identifies CORS endpoints",
      runner: CorsTagger,
    },
    soap: {
      name:   "SOAP Tagger",
      desc:   "Identifies SOAP endpoints",
      runner: SoapTagger,
    },
    websocket: {
      name:   "Websocket Tagger",
      desc:   "Identifies Websocket endpoints",
      runner: WebsocketTagger,
    },
  }

  def self.taggers
    HasTaggers
  end

  def self.run_tagger(endpoints : Array(Endpoint), options : Hash(String, YAML::Any), use_taggers : String)
    tagger_list = [] of Tagger # This will hold instances of taggers

    # Define taggers by creating instances
    # Assuming HuntParamTagger is defined and is the only tagger
    HasTaggers.each_value do |tagger|
      if tagger[:runner].class.to_s == "Class"
        instance = tagger[:runner].new(options)
        tagger_list << instance
      end
    end

    # Parsing use_taggers
    use_taggers_arr = use_taggers.split(",")
    use_taggers_arr = use_taggers_arr.map(&.strip)

    # Run taggers
    tagger_list.each do |tagger|
      tagger.perform(endpoints) if use_taggers_arr.includes?(tagger.name) || use_taggers_arr.includes?("all")
    end
  end
end
