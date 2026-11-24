require "../../../models/access"

# Reads the Ruby guards the Ruby auth tagger recognises into a requirement:
# Devise's `authenticate_<mapping>!` and routes helpers, Rolify role checks,
# CanCanCan `authorize!`, and the conditions that can lift a callback.
module RubyAccess
  extend self

  SIGNED_IN = [Access::Atom.new(:authenticated)]

  def unresolved(text : String) : Access::CNF
    [[Access::Atom.new(:unresolved, text.strip)]]
  end

  # Signed in, plus a check noir did not read.
  def signed_in_and(text : String) : Access::CNF
    [SIGNED_IN] + unresolved(text)
  end

  # A library authentication callback the tagger trusts by name. Devise's
  # `authenticate_<mapping>!` runs `warden.authenticate!(scope: <mapping>)`
  # and nothing else (lib/devise/controllers/helpers.rb, `define_helpers`).
  # `user` is the default model; another mapping (`admin`) is a separate
  # account type, so its name stays unresolved beside the sign-in.
  def library_callback(name : String) : Access::CNF
    name == "authenticate_user!" ? [SIGNED_IN] : signed_in_and(name)
  end

  # Each clause also holds when `condition` lets the caller past: a
  # `skip_before_action ..., if:`, an `if:` / `unless:` on the callback or an
  # app setting that decides whether the callback runs.
  def lifted(cnf : Access::CNF, condition : String) : Access::CNF
    Access.either(cnf, unresolved(condition))
  end

  # Rolify's `has_role?(name)` with no resource holds when the user has a
  # role of that name (lib/rolify/role.rb). A role named by anything but a
  # literal, a resource argument or another check is the app's. Only
  # `current_user` is the caller: `@user` is as often a loaded record.
  ROLIFY = /\Acurrent_user\s*&?\.\s*has_role\?\s*\(?\s*(?::(\w+)|"(\w+)"|'(\w+)')\s*\)?\z/
  CALLER = /\A(?:current_user|user_signed_in\?|signed_in\?|logged_in\?)\z/

  # The role check a callback refuses on: `raise ... unless current_user &&
  # current_user.has_role?(:admin)` refuses unless every conjunct holds.
  # `refuses_when_true` is how the deny reads `condition` (`if` / `unless`).
  def role_check(condition : String, refuses_when_true : Bool) : Access::CNF
    required = condition.strip
    if refuses_when_true
      # `if !current_user.has_role?(:admin)`: the negation is what it needs.
      return unresolved(condition) if !required.starts_with?('!') || required.includes?("&&") || required.includes?("||")
      required = required.lchop('!').strip
    end
    return unresolved(condition) if required.includes?("||") || required.matches?(/\bor\b|\bnot\b/)
    required.split(/&&|\band\b/).map(&.strip).flat_map do |term|
      if term.matches?(CALLER)
        [SIGNED_IN]
      elsif m = term.match(ROLIFY)
        [[Access::Atom.new(:role, m[1]? || m[2]? || m[3])]]
      else
        unresolved(term)
      end
    end.uniq!
  end

  # CanCanCan's `authorize!(action, subject)` raises `AccessDenied` unless
  # the ability grants that action on that subject: `authorize! :read, Doc`
  # asks `read:Doc`. A record (`@post`) is checked by its runtime class,
  # which its name does not settle, so that call stays unresolved. The
  # ability is built for a guest too (the documented `user ||= User.new`,
  # then `can :read, :all`), so unless `guest_refused` a guest may hold it.
  CANCAN_CLASS = /\Aauthorize!\s*\(?\s*:(\w+[?!]?)\s*,\s*((?:::)?[A-Z][\w:]*)\s*\)?\z/

  def cancan_authorize(call : String, guest_refused : Bool) : Access::CNF
    return unresolved(call) unless m = call.strip.match(CANCAN_CLASS)
    permission = Access::Atom.new(:permission, "#{m[1]}:#{m[2].lchop("::")}")
    return [[permission]] if guest_refused
    [[permission, Access::Atom.new(:unresolved, "whether the ability grants :#{m[1]} on #{m[2].lchop("::")} to a guest")]]
  end

  # Devise's `authenticate scope, block` and `authenticated scope, block`
  # routes helpers wrap their routes in a constraint that runs
  # `warden.authenticate!` (or `authenticate?`) for the scope, then the
  # block on the signed-in record (lib/devise/rails/routes.rb,
  # `constraints_for`). No scope is Devise's default one. `authenticated`
  # only stops the route matching: another route may serve the request.
  def devise_route(helper : String, line : String) : Access::CNF
    args = line.sub(/\A#{helper}\b/, "").sub(/\bdo\s*(?:\|[^|]*\|)?\s*\z/, "").strip
    args = args[1...-1].strip if args.starts_with?('(') && args.ends_with?(')')
    cnf = [SIGNED_IN]
    cnf += unresolved("#{helper} #{args}") unless args.empty? || args == ":user"
    cnf += unresolved("#{helper} (a routing constraint: other callers fall through to the next matching route)") if helper == "authenticated"
    cnf
  end
end
