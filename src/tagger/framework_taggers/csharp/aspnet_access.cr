require "../../../models/access"
require "../../../utils/top_level_split"
require "../../../minilexers/csharp_lexer"
require "../../../miniparsers/csharp_decl_parser"

# Reads ASP.NET Core's authorization vocabulary into a requirement:
# `[Authorize(...)]` arguments, `.RequireAuthorization(...)` arguments,
# `AuthorizationPolicyBuilder` chains, and FastEndpoints' `Configure()`
# calls. A named policy is defined elsewhere, so it stays unresolved.
module AspnetAccess
  extend self

  AUTHENTICATED = [[Access::Atom.new(:authenticated)]]
  SPLIT         = Noir::TopLevelSplit::Rules.new(empties: Noir::TopLevelSplit::Empties::DropAll)
  # `Roles = x` (a property) or `policy: x` (a constructor parameter).
  ARGUMENT_KEY  = /\A@?([A-Za-z_]\w*)\s*(?:=(?![=>])|:(?!:))\s*/
  NEW_AUTHORIZE = /\Anew\s+(?:[\w.]+\.)?AuthorizeAttribute\s*(?:\((.*?)\))?\s*(?:\{(.*)\})?\s*\z/m
  LAMBDA        = /\A\(?\s*(\w+)\s*\)?\s*=>\s*(.+)\z/m
  BUILDER       = /\A\s*new\s+(?:[\w.]+\.)?AuthorizationPolicyBuilder\s*\(/

  DEFAULT_POLICY = /\bDefaultPolicy\s*=(?![=>])[^;]*/

  # A `DefaultPolicy = ...` assignment in `code`, without the `)` of the
  # call it sits in.
  def default_policy_assignment(code : String) : String?
    text = code.match(DEFAULT_POLICY).try(&.[0].strip) || return
    while text.ends_with?(')') && text.count(')') > text.count('(')
      text = text.rchop(')').rstrip
    end
    text
  end

  # What the default policy requires: a signed-in user, unless the code
  # replaces it (`assignment`), which noir does not follow.
  def default_policy(assignment : String?) : Access::CNF
    assignment ? [[Access::Atom.new(:unresolved, assignment)]] : AUTHENTICATED
  end

  # The argument text of `[Authorize(...)]`, nil without parentheses.
  # ASP.NET's `AuthorizationPolicy.CombineAsync` adds the default policy only
  # when the attribute names neither roles nor a policy; `default` is what
  # that policy requires.
  def authorize(args : String?, default : Access::CNF = AUTHENTICATED) : Access::CNF
    cnf = Access::CNF.new
    narrowed = false
    parts(args).each do |part|
      key, value = argument(part)
      case key.try(&.downcase)
      when "roles"
        narrowed = true
        cnf << roles(value, part)
      when "policy", nil
        narrowed = true
        cnf << [policy_atom(value)]
      when "authenticationschemes"
      else
        cnf << [unresolved(part)]
      end
    end
    narrowed ? cnf : cnf + default
  end

  # The argument text of `.RequireAuthorization(...)`: no argument is the
  # default policy, and every policy name, `AuthorizeAttribute` or policy
  # builder passed applies.
  def require_authorization(args : String?, default : Access::CNF = AUTHENTICATED) : Access::CNF
    parts = parts(args)
    return default if parts.empty?
    parts.flat_map { |part| requirement(part, default) }
  end

  # An `AuthorizationPolicyBuilder` chain: `p.RequireRole("A")...` read from
  # its `receiver`, or `new AuthorizationPolicyBuilder().Require...()`. Each
  # requirement is a clause; one this does not know is unresolved.
  def policy(text : String, receiver : String? = nil) : Access::CNF
    source = text.strip
    links = links(source, receiver) || return [[unresolved(source)]]
    cnf = Access::CNF.new
    links.each do |name, args|
      case name
      when "RequireAuthenticatedUser"
        cnf << (args.blank? ? [Access::Atom.new(:authenticated)] : [unresolved("#{name}(#{args})")])
      when "RequireRole"
        cnf << list(args, "#{name}(#{args})") { |value| Access::Atom.new(:role, value) }
      when "AddAuthenticationSchemes", "Build"
      else
        cnf << [unresolved("#{name}(#{args})")]
      end
    end
    cnf.empty? ? [[unresolved(source)]] : cnf
  end

  FASTENDPOINTS_CALL = /\b(Roles|Permissions|PermissionsAll|Scopes|ScopesAll|Claims|ClaimsAll|Policies|Policy|AuthSchemes)\s*\(/

  # A FastEndpoints `Configure()` body of an endpoint that does not allow
  # anonymous callers. Per FastEndpoints' `EndpointDefinition` and
  # `EndpointSecurityPolicies`, every call adds to one list per kind (the
  # last `X` / `XAll` call decides whether any or all of it is needed), the
  # endpoint policy always requires an authenticated user, and roles, each
  # named policy and each policy builder apply on top of it. An endpoint
  # calling none of them gets a bare `RequireAuthorization()` from
  # `EndpointRouteMapper`: the default policy.
  def fastendpoints(block : String, default : Access::CNF = AUTHENTICATED) : Access::CNF
    lexer = Noir::CSharpLexer.new(block)
    masked = lexer.masked_source
    roles = [] of Access::Atom
    kinds = {
      "Permissions" => {[] of Access::Atom, true},
      "Scopes"      => {[] of Access::Atom, true},
      "Claims"      => {[] of Access::Atom, true},
    }
    cnf = Access::CNF.new
    secured = false
    masked.scan(FASTENDPOINTS_CALL) do |call|
      secured = true
      open = call.end(0) - 1
      close = lexer.matching_delimiter(open) || next
      name = call[1]
      args = block[open + 1...close]
      case name
      when "AuthSchemes"
      when "Roles"
        parts(args).each { |value| roles << atom(value, :role) }
      when "Policies"
        parts(args).each { |value| cnf << [policy_atom(value)] }
      when "Policy"
        builder = args.strip.match(LAMBDA)
        cnf.concat(builder ? policy(builder[2], builder[1]) : [[unresolved("#{name}(#{args})")]])
      else
        kind = name.rchop("All")
        values, _ = kinds[kind]
        parts(args).each do |value|
          values << (kind == "Claims" ? Access::Atom.new(:unresolved, "claim type #{literal(value) || value}") : atom(value, kind == "Scopes" ? Access::Kind::Scope : Access::Kind::Permission))
        end
        kinds[kind] = {values, !name.ends_with?("All")}
      end
    end
    cnf << roles unless roles.empty?
    kinds.each_value do |values, any|
      next if values.empty?
      any ? (cnf << values) : values.each { |value| cnf << [value] }
    end
    (secured ? AUTHENTICATED : default) + cnf
  end

  private def requirement(part : String, default : Access::CNF) : Access::CNF
    if name = literal(part)
      [[Access::Atom.new(:unresolved, "Policy=#{name}")]]
    elsif found = part.match(NEW_AUTHORIZE)
      authorize([found[1]?, found[2]?].compact.reject(&.blank?).join(", "), default)
    elsif found = part.match(LAMBDA)
      policy(found[2], found[1])
    else
      [[unresolved(part)]]
    end
  end

  # `{name, arguments}` of each `.Name(...)` link after the receiver; nil
  # when the text is not one whole chain.
  private def links(source : String, receiver : String?) : Array(Tuple(String, String))?
    lexer = Noir::CSharpLexer.new(source)
    masked = lexer.masked_source
    pos =
      if receiver
        found = masked.match(/\A#{Regex.escape(receiver)}\b/) || return
        found.end(0)
      elsif found = masked.match(BUILDER)
        (lexer.matching_delimiter(found.end(0) - 1) || return) + 1
      else
        return
      end
    links = [] of Tuple(String, String)
    while link = masked.match(/\G\s*\.\s*(\w+)\s*\(/, pos)
      close = lexer.matching_delimiter(link.end(0) - 1) || return
      links << {link[1], source[link.end(0)...close]}
      pos = close + 1
    end
    masked[pos..].strip.rchop(';').blank? ? links : nil
  end

  # ASP.NET would fail on an empty role list, so a blank `Roles` is left
  # unread rather than taken for no requirement.
  private def roles(value : String, part : String) : Array(Access::Atom)
    return [unresolved(part)] unless text = literal(value)
    names = text.split(',').map(&.strip).reject(&.empty?)
    names.empty? ? [unresolved(part)] : names.map { |name| Access::Atom.new(:role, name) }
  end

  private def list(args : String, source : String, & : String -> Access::Atom) : Array(Access::Atom)
    values = parts(args)
    return [unresolved(source)] if values.empty?
    values.map { |value| (text = literal(value)) ? yield(text) : unresolved(value) }
  end

  private def atom(value : String, kind : Access::Kind) : Access::Atom
    (text = literal(value)) ? Access::Atom.new(kind, text) : unresolved(value)
  end

  private def policy_atom(value : String) : Access::Atom
    (name = literal(value)) ? Access::Atom.new(:unresolved, "Policy=#{name}") : unresolved(value)
  end

  private def argument(part : String) : Tuple(String?, String)
    (found = part.match(ARGUMENT_KEY)) ? {found[1], part[found.end(0)..]} : {nil, part}
  end

  private def parts(args : String?) : Array(String)
    args ? Noir::TopLevelSplit.split(args, ',', SPLIT) : [] of String
  end

  private def literal(text : String) : String?
    Noir::CSharpDecl.literal(text)
  end

  private def unresolved(fragment : String) : Access::Atom
    Access::Atom.new(:unresolved, fragment.strip)
  end
end
