require "json"
require "crest"

module LLM
  class Ollama
    def initialize(url : String, model : String)
      @url = url
      @api = @url + "/api/generate"
      @model = model
      @contexts = Hash(String, Array(Int32)).new
    end

    def request(prompt : String, format : String = "json")
      body = {
        :model       => @model,
        :prompt      => prompt,
        :stream      => false,
        :temperature => 0.3,
        :format      => format == "json" ? "json" : JSON.parse(format),
      }

      response = Crest.post(@api, body, json: true)
      response_json = JSON.parse response.body

      response_json["response"].to_s
    rescue ex : Exception
      puts "Error: #{ex.message}"

      ""
    end

    def request_with_context(system : String?, user : String, format : String = "json", cache_key : String? = nil)
      prompt = if system && !system.empty?
                 "#{system}\n\n#{user}"
               else
                 user
               end

      body = {
        :model       => @model,
        :prompt      => prompt,
        :stream      => false,
        :temperature => 0.3,
        :format      => format == "json" ? "json" : JSON.parse(format),
      }

      if cache_key && (ctx = @contexts[cache_key]?)
        body[:context] = JSON.parse(ctx.to_json)
      end

      response = Crest.post(@api, body, json: true)
      response_json = JSON.parse response.body

      if cache_key && (rc = response_json["context"]?)
        begin
          arr = rc.as_a.map(&.as_i)
          @contexts[cache_key] = arr
        rescue
          # ignore malformed or unexpected context
        end
      end

      response_json["response"].to_s
    rescue ex : Exception
      puts "Error: #{ex.message}"

      ""
    end

    def query(code : String)
      request(PROMPT + "\n" + code)
    end
  end
end
