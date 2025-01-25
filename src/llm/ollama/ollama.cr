require "json"

module LLM
  class Ollama
    def initialize(url : String, model : String)
      @url = url
      @api = @url + "/api/generate"
      @model = model
    end

    def request(prompt : String)
      body = {
        :model  => @model,
        :prompt => prompt,
        :stream => false,
      }

      response = Crest.post(@api, body, json: true)
      response_json = JSON.parse response.body

      response_json["response"]
    rescue ex : Exception
      puts "Error: #{ex.message}"

      ""
    end

    def request_with_format(prompt : String, format : String)
      body = {
        :model  => @model,
        :prompt => prompt,
        :stream => false,
        :format => JSON.parse(format),
        :temperature => 0.5,
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
