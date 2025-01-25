require "json"

module LLM
  class Ollama
    def initialize(url : String, model : String)
      @url = url
      @api = @url + "/api/generate"
      @model = model
    end

    def request(prompt : String, format : String = "json")
      body = {
        :model  => @model,
        :prompt => prompt,
        :stream => false,
        :temperature => 0.3,
        :format => format == "json" ? "json" : JSON.parse(format)
      }

      response = Crest.post(@api, body, json: true)
      response_json = JSON.parse response.body

      response_json["response"]
    rescue ex : Exception
      puts "Error: #{ex.message}"

      ""
    end

    def query(code : String)
      request(PROMPT + "\n" + code)
    end
  end
end
