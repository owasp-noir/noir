require "acp"
require "json"
require "log"

module LLM
  # ACP-backed client wrapper for communicating with local AI agents.
  class ACPClient
    getter provider : String
    getter model : String
    getter command : String
    getter args : Array(String)

    @client : ACP::Client?
    @session : ACP::Session?
    @agent_stderr : IO?
    @session_lock : Mutex
    @response_lock : Mutex
    @response_buffer : String

    @@logs_muted = false
    @@logs_mutex = Mutex.new

    CODEX_ARGS  = ["@zed-industries/codex-acp"]
    GEMINI_ARGS = ["--experimental-acp"]
    CLAUDE_ARGS = ["@zed-industries/claude-code-acp"]

    def initialize(@provider : String, @model : String, @event_sink : Proc(String, Nil)? = nil)
      @command, @args = self.class.resolve_command(provider)
      @session_lock = Mutex.new
      @response_lock = Mutex.new
      @response_buffer = ""
      self.class.mute_acp_logs
    end

    def self.acp_provider?(provider : String) : Bool
      provider.downcase.starts_with?("acp:")
    end

    def self.extract_target(provider : String) : String
      parts = provider.split(":", 2)
      return provider.strip if parts.size < 2
      parts[1].strip
    end

    def self.default_model(provider : String, model : String) : String
      return model unless model.empty?
      target = extract_target(provider)
      target.empty? ? "acp" : target
    end

    # Resolve provider aliases to actual executable command + args.
    def self.resolve_command(provider : String) : Tuple(String, Array(String))
      target = extract_target(provider)
      normalized = target.downcase
      case normalized
      when "codex"
        {"npx", CODEX_ARGS.clone}
      when "gemini"
        {"gemini", GEMINI_ARGS.clone}
      when "claude", "claude-code"
        {"npx", CLAUDE_ARGS.clone}
      else
        {target.empty? ? "acp" : target, [] of String}
      end
    end

    def request_messages(messages : Array(Hash(String, String)), format : String = "json") : String
      request(messages_to_prompt(messages), format)
    end

    def request(prompt : String, format : String = "json") : String
      session = ensure_session
      clear_response_buffer
      final_prompt = append_format_instruction(prompt, format)
      session.prompt(final_prompt)
      clean_response(read_response_buffer)
    rescue Exception
      close
      ""
    end

    def close : Nil
      @session_lock.synchronize do
        begin
          @event_sink.try(&.call("ACP: closing client"))
          @client.try(&.close)
          @agent_stderr.try(&.close)
        rescue Exception
        ensure
          @client = nil
          @session = nil
          @agent_stderr = nil
        end
      end
    end

    private def ensure_session : ACP::Session
      if session = @session
        return session
      end

      @session_lock.synchronize do
        if @session.nil?
          agent_stderr = if ENV["NOIR_ACP_RAW_LOG"]? == "1"
                           STDERR
                         else
                           File.open(File::NULL, "w")
                         end
          transport = ACP::ProcessTransport.new(
            @command,
            args: @args,
            stderr: agent_stderr
          )
          client = ACP::Client.new(transport, client_name: "noir")
          client.on_update = ->(update : ACP::Protocol::SessionUpdateParams) do
            case u = update.update
            when ACP::Protocol::AgentMessageChunkUpdate
              append_response(u.text)
            end
            nil
          end
          client.on_agent_request = ->(method : String, _params : JSON::Any) do
            if method == "session/request_permission"
              JSON.parse(%({"outcome":{"outcome":"selected","optionId":"allow-once"}}))
            else
              JSON.parse(%({}))
            end
          end
          client.initialize_connection
          if ai = client.agent_info
            @event_sink.try(&.call("ACP: connected to #{ai.name} v#{ai.version}"))
          else
            @event_sink.try(&.call("ACP: connected"))
          end
          session = ACP::Session.create(client, cwd: (ENV["NOIR_ACP_CWD"]? || Dir.current))
          @event_sink.try(&.call("ACP: session #{session.id} created"))

          @client = client
          @session = session
          @agent_stderr = agent_stderr.same?(STDERR) ? nil : agent_stderr
        end
      end

      @session.not_nil!
    end

    def self.mute_acp_logs : Nil
      return if ENV["NOIR_ACP_RAW_LOG"]? == "1"

      @@logs_mutex.synchronize do
        return if @@logs_muted
        ::Log.for("acp.client").level = ::Log::Severity::None
        ::Log.for("acp.transport").level = ::Log::Severity::None
        @@logs_muted = true
      end
    end

    private def messages_to_prompt(messages : Array(Hash(String, String))) : String
      sections = [] of String
      messages.each do |m|
        role = m["role"]? || "user"
        content = m["content"]?
        next if content.nil? || content.empty?
        sections << "#{role.upcase}:\n#{content}"
      end
      sections.join("\n\n")
    end

    private def append_format_instruction(prompt : String, format : String) : String
      return prompt if format.empty?

      if format == "json"
        "#{prompt}\n\nReturn only valid JSON. Do not wrap output in markdown code fences."
      else
        [
          prompt,
          "Return only valid JSON following this schema/format requirement:",
          format,
          "Do not wrap output in markdown code fences.",
        ].join("\n\n")
      end
    end

    private def clear_response_buffer : Nil
      @response_lock.synchronize do
        @response_buffer = ""
      end
    end

    private def append_response(chunk : String) : Nil
      @response_lock.synchronize do
        @response_buffer += chunk
      end
    end

    private def read_response_buffer : String
      @response_lock.synchronize do
        @response_buffer.dup
      end
    end

    private def clean_response(raw : String) : String
      raw.gsub("```json", "").gsub("```", "").strip
    end
  end
end
