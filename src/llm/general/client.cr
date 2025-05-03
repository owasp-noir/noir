require "json"

module LLM
  class General
    def initialize(url : String, model : String, api_key : String?)
      @url = url
      @api = if url.includes?("://")
               url
             else
               case url.downcase
               when "openai"
                 "https://api.openai.com/v1/chat/completions"
               when "ollama"
                 "http://localhost:11434/v1/chat/completions"
               when "lmstudio"
                 "http://localhost:1234/v1/chat/completions"
               when "xai"
                 "https://api.x.ai/v1/chat/completions"
               when "vllm"
                 "http://localhost:8000/v1/chat/completions"
               when "azure"
                 "https://models.inference.ai.azure.com/chat/completions"
               when "github"
                 "https://models.github.ai/inference/chat/completions"
               else
                 url
               end
             end

      @model = model
      @api_key = api_key || ENV["NOIR_AI_KEY"]
    end

    def request(prompt : String, format : String = "json", temperature : Float64 = 0.3)
      body = {
        "model"           => @model,
        "messages"        => [{"role" => "user", "content" => prompt}],
        "temperature"     => temperature,
        "stream"          => false,
        "response_format" => format == "json" ? {"type" => "json_object"} : JSON.parse(format),
      }.to_json

      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      headers["Authorization"] = "Bearer #{@api_key}" if @api_key

      response = HTTP::Client.post(@api, headers: headers, body: body)
      response_json = JSON.parse(response.body)

      if response_json.as_h.has_key?("error")
        if response_json["error"].as_h.has_key?("message")
          if response_json["error"]["message"].as_s.includes?("'temperature' does not support #{temperature}") && temperature != 1.0
            temperature = 1.0
            return request(prompt, format, temperature)
          end
        end

        puts "LLM Request Error: #{response_json["error"]}"
        return ""
      end

      response_json["choices"][0]["message"]["content"].to_s.gsub("```json", "").gsub("```", "").strip
    rescue ex : Exception
      puts "Error: #{ex.message}"
      puts response_json
      ""
    end

    def query(code : String)
      request(PROMPT + "\n" + code)
    end
  end
end
