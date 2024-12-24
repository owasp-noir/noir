module LLM
  class Ollama
    def initialize(url : String, model : String)
      @url = url
      @api = @url + "/api/generate"
      @model = model
    end

    def request(prompt : String)
      body = {
        :model => @model,
        :prompt => prompt
      }

      response = Crest.post(@api, body, json: true)
      response.body
    rescue ex : Exception
      puts "Error: #{ex.message}"
    end

    def query(code : String)
      request(PROMPT + "\n" + code)
    end
  end
end