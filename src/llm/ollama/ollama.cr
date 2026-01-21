require "json"
require "crest"

module LLM
  # Ollama LLM client with context-aware request support
  class Ollama
    def initialize(url : String, model : String)
      @url = url
      @api = @url + "/api/generate"
      @model = model
      @contexts = Hash(String, Array(Int32)).new
    end

    # Make a simple request without context management
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
      logger.debug ex
      ""
    end

    # Make a request with optional context management for improved efficiency
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

      # Reuse context if available
      if cache_key && (ctx = @contexts[cache_key]?)
        body[:context] = JSON.parse(ctx.to_json)
      end

      response = Crest.post(@api, body, json: true)
      response_json = JSON.parse response.body

      # Store context for future reuse
      if cache_key && (rc = response_json["context"]?)
        begin
          arr = rc.as_a.map(&.as_i)
          @contexts[cache_key] = arr
        rescue
          # Ignore malformed or unexpected context
        end
      end

      response_json["response"].to_s
    rescue ex : Exception
      logger.debug ex
      ""
    end
  end
end
