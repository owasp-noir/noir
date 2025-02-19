require "json"

module LLM
  class OpenAI
    def initialize(url : String, model : String, api_key : String?)
      @url = url
      @api = @url + "/v1/chat/completions"
      @model = model
      @api_key = api_key
    end

    def request(prompt : String, format : String = "json")
      body = {
        "model"           => @model,
        "messages"        => [{"role" => "user", "content" => prompt}],
        "temperature"     => 0.3,
        "stream"          => false,
        "response_format" => format == "json" ? {"type" => "json_object"} : JSON.parse(format),
      }.to_json

      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      headers["Authorization"] = "Bearer #{@api_key}" if @api_key

      response = HTTP::Client.post(@api, headers: headers, body: body)
      response_json = JSON.parse(response.body)

      response_json["choices"][0]["message"]["content"].to_s
    rescue ex : Exception
      puts "Error: #{ex.message}"
      ""
    end

    def query(code : String)
      request(PROMPT + "\n" + code)
    end
  end
end
