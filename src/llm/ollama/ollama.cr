require "json"
require "../http_transport"
require "../response_cleanup"
require "../sampling"

module LLM
  # Ollama LLM client (native `/api/generate`)
  class Ollama
    # Endpoint extraction wants the model to read code, not to write
    # prose about it, so both request paths pin a low temperature.
    TEMPERATURE = 0.3

    # `format: "json"` — Ollama's plain JSON mode.
    JSON_MODE = JSON::Any.new("json")

    # `context_tokens` is the token budget the caller sized its prompts for.
    # Ollama otherwise runs at its own 2-4k default `num_ctx` and silently
    # drops the start of anything longer, so a bundle sized for a 128k model
    # lost most of its files. One fixed value per client, rounded up to
    # 1024: a `num_ctx` that changes between requests reloads the model.
    @num_ctx : Int32?
    @api_key : String?

    def initialize(url : String, model : String, context_tokens : Int32? = nil, api_key : String? = nil)
      @url = url
      @api = "#{url.chomp("/")}/api/generate"
      @model = model
      # Same resolution as LLM::General: a hosted Ollama or an
      # authenticating proxy needs the bearer token.
      @api_key = api_key.presence || ENV["NOIR_AI_KEY"]?.presence
      @num_ctx = context_tokens.try { |tokens| tokens > 0 ? (tokens + 1023) // 1024 * 1024 : nil }
    end

    def request(prompt : String, format : String = "json")
      post(build_body(prompt, format))
    end

    # No KV `context` is chained between calls: every caller sends
    # independent prompts, and feeding file N's context into file N+1 made
    # each answer depend on traversal order.
    def request_with_context(system : String?, user : String, format : String = "json")
      prompt = if system && !system.empty?
                 "#{system}\n\n#{user}"
               else
                 user
               end
      post(build_body(prompt, format))
    end

    # Ollama's `format` field takes either the literal string "json" or a
    # raw JSON Schema, and uses a schema to constrain decoding. The formats
    # in `LLM::*` are OpenAI-shaped envelopes
    # (`{"type":"json_schema","json_schema":{"schema":{...}}}`); handing
    # that envelope straight to Ollama constrained generation to the
    # *envelope* rather than to the endpoint object we asked for, so the
    # response never matched what the analyzer parses — every endpoint in
    # the request was lost. Unwrap to the inner schema, and fall back to
    # plain JSON mode for anything we don't recognise.
    def self.format_value(format : String) : JSON::Any
      return JSON_MODE if format.empty? || format == "json"

      hash = JSON.parse(format).as_h?
      return JSON_MODE if hash.nil?

      if envelope = hash["json_schema"]?
        inner = envelope.as_h?.try(&.["schema"]?)
        return inner || JSON_MODE
      end

      # A bare JSON Schema can be passed through as-is; an envelope we
      # failed to unwrap cannot.
      return JSON_MODE if hash["type"]?.try(&.as_s?) == "json_schema"
      JSON::Any.new(hash)
    rescue JSON::ParseException
      JSON_MODE
    end

    private def build_body(prompt : String, format : String) : String
      JSON.build do |json|
        json.object do
          json.field "model", @model
          json.field "prompt", prompt
          json.field "stream", false
          json.field "format" do
            self.class.format_value(format).to_json(json)
          end
          # Generation settings live under `options` in the Ollama API. The
          # top-level `temperature` this used to send was silently dropped,
          # so every request ran at the model's default (0.8) — measurably
          # more invented endpoints than the 0.3 we asked for.
          json.field "options" do
            json.object do
              json.field "temperature", LLM::Sampling.temperature || TEMPERATURE
              LLM::Sampling.seed.try { |seed| json.field "seed", seed }
              @num_ctx.try { |num_ctx| json.field "num_ctx", num_ctx }
            end
          end
        end
      end
    end

    private def post(body : String) : String
      raw = LLM::HttpTransport.post_json(@api, body, request_headers)
      return "" if raw.nil?

      response_json = JSON.parse(raw)
      if error = response_json["error"]?
        STDERR.puts "WARNING: Ollama error: #{LLM::HttpTransport.truncate_error_snippet(error.to_s)}"
        return ""
      end

      text = response_json["response"]?.try(&.to_s) || ""
      LLM.unfinished_reply(response_json["done_reason"]?.try(&.as_s?), text).try { |warning| STDERR.puts "WARNING: #{warning}" }
      text
    rescue e : Exception
      # Previously a bare `rescue Exception` returning "" — an unreachable
      # server, a wrong model name and a malformed reply were all reported
      # to the user as "this project has no endpoints".
      STDERR.puts "WARNING: Ollama response could not be processed (#{e.message})"
      ""
    end

    private def request_headers : HTTP::Headers
      headers = HTTP::Headers.new
      headers["Content-Type"] = "application/json"
      @api_key.try { |key| headers["Authorization"] = "Bearer #{key}" }
      headers
    end
  end
end
