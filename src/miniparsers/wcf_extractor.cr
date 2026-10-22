require "../minilexers/csharp_lexer"
require "../utils/top_level_split"

module Noir
  # Code-first WCF REST operations: `[WebGet]` / `[WebInvoke]` on a service
  # contract method (System.ServiceModel.Web, or CoreWCF.Web). Yields
  # declarations only; turning a UriTemplate into a URL is the analyzer's job.
  module WcfExtractor
    extend self

    # `uri_template` nil means "not declared": WCF then serves the operation
    # on its name (`name`). `params` are the operation's wire parameter names.
    record Operation,
      verb : String,
      uri_template : String?,
      name : String,
      params : Array(String),
      line : Int32

    # `[WebGet(...)]`, `[OperationContract, WebInvoke(...)]`, `[WebGet]`.
    ATTRIBUTE = /[\[,]\s*(?:[\w.]+\.)?Web(Get|Invoke)(?:Attribute)?\s*(?=[(\],])/
    # The method name before the parameter list, past a generic `<T>`.
    METHOD_NAME = /(\w+)\s*(?:<[^()]*>)?\s*\z/
    # `[OperationContract(Name = "x")]` / `[MessageParameter(Name = "x")]`
    # rename the operation / parameter on the wire.
    CONTRACT_NAME = /\bOperationContract(?:Attribute)?\s*\([^)]*\bName\s*=\s*@?"([^"]+)"/
    MESSAGE_PARAM = /\bMessageParameter(?:Attribute)?\s*\([^)]*\bName\s*=\s*@?"([^"]+)"/
    KEYWORD_ARG   = /\A(\w+)\s*=\s*(.*)\z/m
    LITERAL       = /\A@?"((?:[^"\\]|\\.|"")*)"\z/m
    ARGS          = TopLevelSplit::Rules.new(quotes: "\"")

    # Every WCF operation also carries `[OperationContract]`, so a file with
    # a `WebGet` attribute but no contract is someone else's attribute.
    def wcf_source?(content : String) : Bool
      content.includes?("OperationContract") && content.matches?(ATTRIBUTE)
    end

    def extract(content : String) : Array(Operation)
      operations = [] of Operation
      return operations unless wcf_source?(content)

      lexer = CSharpLexer.new(content)
      # Attributes are found on the masked view (a commented-out or quoted
      # `[WebGet]` is blank there); argument text comes from the code view,
      # which is character-aligned with it but keeps the string literals.
      masked = lexer.masked_source
      chars = masked.chars
      code = lexer.code_source.chars
      line = 1
      scanned = 0

      masked.scan(ATTRIBUTE) do |m|
        start = m.begin(0)
        line += chars[scanned...start].count('\n')
        scanned = start

        verb = m[1] == "Get" ? "GET" : "POST"
        template = nil
        after = m.end(0)
        if chars[after]? == '('
          close = lexer.matching_delimiter(after) || next
          unresolved = false
          TopLevelSplit.split(code[(after + 1)...close].join, ',', ARGS).each do |arg|
            kw = arg.match(KEYWORD_ARG) || next
            value = kw[2].strip
            case kw[1]
            when "UriTemplate"
              next if value == "null"
              template = literal(value)
              unresolved = true unless template
            when "Method"
              # `Method = WebRequestMethods.Http.Put` names the verb last.
              verb = (literal(value) || value.split('.').last).upcase
            end
          end
          # A template held in a constant cannot be resolved here, and the
          # operation-name fallback would report a path WCF never serves.
          next if unresolved
          after = close + 1
        end

        paren = signature_paren(lexer, chars, after) || next
        # Everything from the end of the previous member to the parameter
        # list: the attribute sections plus the method signature.
        head = start > 0 ? (chars.rindex(start - 1, &.in?(';', '{', '}')) || -1) + 1 : 0
        declaration = code[head...paren].join
        # WCF strips `Async` off a Task-based operation's name.
        name = declaration.match(CONTRACT_NAME).try(&.[1]) ||
               declaration.match(METHOD_NAME).try(&.[1].rchop("Async")) || next
        params_close = lexer.matching_delimiter(paren) || next
        params = TopLevelSplit.split(code[(paren + 1)...params_close].join, ',', TopLevelSplit::Rules::CSHARP_PARAMS).compact_map do |param|
          param.match(MESSAGE_PARAM).try(&.[1]) ||
            param.sub(/\A(?:\s*\[[^\]]*\])*/, "").split('=').first.scan(/\w+/).last?.try(&.[0])
        end

        operations << Operation.new(verb, template, name, params, line)
      end

      operations
    end

    # The `(` opening the parameter list of the method the attribute section
    # around `pos` decorates. Further attribute sections (and array brackets
    # in the return type) are skipped; a `;`/`{`/`}` first means the
    # attribute sits on something that is not a method.
    private def signature_paren(lexer : CSharpLexer, chars : Array(Char), pos : Int32) : Int32?
      in_section = true
      i = pos
      while i < chars.size
        c = chars[i]
        if in_section
          case c
          when '(' then i = lexer.matching_delimiter(i) || return
          when ']' then in_section = false
          end
        else
          case c
          when '['           then in_section = true
          when '('           then return i
          when ';', '{', '}' then return
          end
        end
        i += 1
      end
    end

    private def literal(value : String) : String?
      value.match(LITERAL).try(&.[1])
    end
  end
end
