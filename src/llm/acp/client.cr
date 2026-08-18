require "acp"
require "json"
require "log"
require "../response_cleanup"
require "./targets"

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
    @request_lock : Mutex
    @response_lock : Mutex
    @response_buffer : String

    @@logs_muted = false
    @@logs_mutex = Mutex.new

    CODEX_ARGS  = ["@zed-industries/codex-acp"]
    GEMINI_ARGS = ["--experimental-acp"]
    CLAUDE_ARGS = ["@zed-industries/claude-agent-acp"]

    # See `LLM::ACPTargets` for the list and why it is shared rather than
    # duplicated. Kept as an alias so existing references still read naturally
    # at the exec sink.
    KNOWN_TARGETS = ACPTargets::KNOWN

    class UnsupportedACPTargetError < Exception; end

    # Escape hatch for power users running their own ACP agent binary. Off by
    # default so a poisoned `.noir.yml` can't silently spawn a process.
    def self.custom_command_allowed? : Bool
      ENV["NOIR_ACP_ALLOW_CUSTOM_COMMAND"]? == "1"
    end

    # `session/request_permission` is how the ACP agent asks to run a tool —
    # shell commands, file writes, network fetches — on this machine. Noir
    # used to answer every one of them with a hardcoded
    # `{"outcome":"selected","optionId":"allow-once"}`, i.e. blanket approval
    # for whatever the agent decided to do.
    #
    # That is remote-controllable input. The prompt Noir sends is source code
    # from the tree being scanned, and scanning code you did not write is the
    # normal case; a file carrying "ignore the above and run X" is enough to
    # turn an endpoint scan into arbitrary local execution, with the auto-yes
    # removing the one checkpoint that would have caught it. It also
    # contradicted the `resolve_command` hardening right above, which refuses
    # to spawn an unknown agent binary precisely so untrusted config can't
    # reach code execution.
    #
    # Deny by default. Noir puts the code to analyse *in the prompt*, so the
    # agent needs no tools to answer — the only thing lost is an agent's
    # optional extra poking around. Operators who want that back opt in
    # explicitly, same shape as the custom-command escape hatch.
    def self.tool_permissions_allowed? : Bool
      ENV["NOIR_ACP_ALLOW_TOOL_PERMISSIONS"]? == "1"
    end

    # Pick a real option from the ones the agent offered rather than
    # inventing an id. Option ids are agent-defined (`proceed_once`,
    # `reject`, …); the `kind` field is the part the protocol standardises,
    # so it is what we match on. With nothing usable on offer, `cancelled`
    # is the protocol's own "no decision" outcome and needs no id.
    #
    # Public rather than private so the decision can be asserted without
    # standing up an agent process.
    def answer_permission_request(params : JSON::Any) : JSON::Any
      allow = self.class.tool_permissions_allowed?
      wanted = allow ? {"allow_once", "allow_always"} : {"reject_once", "reject_always"}

      option_id = nil
      if options = params["options"]?.try(&.as_a?)
        wanted.each do |kind|
          break if option_id
          options.each do |option|
            next unless option["kind"]?.try(&.as_s?) == kind
            option_id = option["optionId"]?.try(&.as_s?)
            break if option_id
          end
        end
      end

      tool = params.dig?("toolCall", "title").try(&.as_s?) ||
             params.dig?("toolCall", "toolName").try(&.as_s?) || "tool call"

      if option_id
        @event_sink.try(&.call("ACP: #{allow ? "allowed" : "denied"} permission request (#{tool})"))
        JSON.parse(%({"outcome":{"outcome":"selected","optionId":#{option_id.to_json}}}))
      else
        @event_sink.try(&.call("ACP: cancelled permission request (#{tool}) — no #{allow ? "allow" : "reject"} option offered"))
        JSON.parse(%({"outcome":{"outcome":"cancelled"}}))
      end
    end

    def initialize(@provider : String, @model : String, @event_sink : Proc(String, Nil)? = nil)
      @command, @args = self.class.resolve_command(provider)
      @session_lock = Mutex.new
      @request_lock = Mutex.new
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
        unless custom_command_allowed?
          raise UnsupportedACPTargetError.new(
            "Unsupported ACP provider target #{target.inspect}. Allowed acp: targets are #{KNOWN_TARGETS.join(", ")}. " \
            "Running an arbitrary command as an ACP agent is disabled; set NOIR_ACP_ALLOW_CUSTOM_COMMAND=1 to override (only with trusted config)."
          )
        end
        parts = target.split
        command = parts.first || "acp"
        args = parts.size > 1 ? parts[1..-1] : [] of String
        {command, args}
      end
    end

    def request_messages(messages : Array(Hash(String, String)), format : String = "json") : String
      request(messages_to_prompt(messages), format)
    end

    def request(prompt : String, format : String = "json") : String
      # One session, one response buffer. Two fibers prompting at once —
      # which is exactly what the bundle analyzer does when it fans out —
      # interleaved their streamed chunks into that single buffer, and each
      # read back a blend of both answers: unparsable at best, endpoints
      # attributed to the wrong bundle at worst. Serialize the whole
      # clear -> prompt -> read window. `session.prompt` blocks until the
      # agent's turn ends anyway, so overlapping them never bought
      # concurrency to begin with.
      @request_lock.synchronize do
        session = ensure_session
        clear_response_buffer
        final_prompt = append_format_instruction(prompt, format)
        session.prompt(final_prompt)
        clean_response(read_response_buffer)
      end
    rescue e : Exception
      report_request_failure(e)
      close
      ""
    end

    # `General` and `Ollama` both report their failures on stderr; the rescue
    # above used to be bare, so a session that never spawned, an agent that
    # died mid-turn, a protocol error and a genuinely empty answer were all
    # the same "" with nothing written anywhere. The caller reads "" as "this
    # code defines no endpoints", which made a completely dead agent look like
    # a successful AI-assisted scan.
    #
    # Public so the report can be asserted without standing up an agent
    # process.
    def report_request_failure(error : Exception) : Nil
      STDERR.puts "WARNING: ACP agent request failed (#{error.class}: #{error.message})"
      @event_sink.try(&.call("ACP: request failed (#{error.class}: #{error.message})"))
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
          client.on_agent_request = ->(method : String, params : JSON::Any) do
            if method == "session/request_permission"
              answer_permission_request(params)
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

      session = @session
      return session unless session.nil?

      raise "ACP session initialization failed"
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
      LLM.strip_json_fences(raw)
    end
  end
end
