require "json"
require "../http_transport"

module LLM
  # Ollama LLM client with context-aware request support
  class Ollama
    # Endpoint extraction wants the model to read code, not to write
    # prose about it, so both request paths pin a low temperature.
    TEMPERATURE = 0.3

    # `format: "json"` — Ollama's plain JSON mode.
    JSON_MODE = JSON::Any.new("json")

    def initialize(url : String, model : String)
      @url = url
      @api = "#{url.chomp("/")}/api/generate"
      @model = model
      @contexts = Hash(String, Array(Int32)).new
    end

    # Make a simple request without context management
    def request(prompt : String, format : String = "json")
      post(build_body(prompt, format, nil))
    end

    # Make a request with optional context management for improved efficiency
    def request_with_context(system : String?, user : String, format : String = "json", cache_key : String? = nil)
      prompt = if system && !system.empty?
                 "#{system}\n\n#{user}"
               else
                 user
               end

      context = cache_key ? @contexts[cache_key]? : nil
      post(build_body(prompt, format, context), cache_key)
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

    private def build_body(prompt : String, format : String, context : Array(Int32)?) : String
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
              json.field "temperature", TEMPERATURE
            end
          end
          if reused = context
            json.field "context" do
              reused.to_json(json)
            end
          end
        end
      end
    end

    private def post(body : String, cache_key : String? = nil) : String
      raw = LLM::HttpTransport.post_json(@api, body, request_headers)
      return "" if raw.nil?

      response_json = JSON.parse(raw)
      if error = response_json["error"]?
        STDERR.puts "WARNING: Ollama error: #{LLM::HttpTransport.truncate_error_snippet(error.to_s)}"
        return ""
      end

      store_context(cache_key, response_json) if cache_key
      response_json["response"]?.try(&.to_s) || ""
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
      headers
    end

    private def store_context(cache_key : String, response_json : JSON::Any) : Nil
      raw_context = response_json["context"]?
      return if raw_context.nil?
      @contexts[cache_key] = raw_context.as_a.map(&.as_i)
    rescue Exception
      # Ignore malformed or unexpected context
    end
  end
end
