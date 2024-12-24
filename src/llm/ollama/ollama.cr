module LLM
  class Ollama
    def initialize(url : String, model : String)
      @url = url
      @api = @url + "/api/generate"
      @model = model
    end

    def request(prompt : String)
      body = {
        "model":  @model,
        "prompt": prompt,
      }

      Crest::Request.execute(
        method: "POST",
        url: @api,
        form: body,
        json: true
      )
    end

    def query(code : String)
    end
  end
end
