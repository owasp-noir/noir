require "../../../models/framework_tagger"
require "../../../models/endpoint"

@[Noir::TaggerFor(key: "flask_auth", name: "Flask Auth Tagger", desc: "Identifies Flask authentication patterns (flask-login, flask-jwt, flask-httpauth)", order: 90)]
class FlaskAuthTagger < FrameworkTagger
  DECORATOR_PATTERNS = [
    {/\@login_required/, "flask-login login_required"},
    {/\@roles_required\s*\(/, "flask-security roles_required"},
    {/\@roles_accepted\s*\(/, "flask-security roles_accepted"},
    # `\b` matches both the bare `@jwt_required` and the `@jwt_required()`
    # call form, both idiomatic in flask-jwt-extended.
    {/\@jwt_required\b/, "flask-jwt-extended jwt_required"},
    {/\@jwt_optional\s*\(/, "flask-jwt-extended jwt_optional"},
    {/\@fresh_jwt_required\s*\(/, "flask-jwt-extended fresh_jwt_required"},
    {/\@auth_required\s*\(/, "flask-security auth_required"},
    {/\@http_auth_required\b/, "flask-security http_auth_required"},
    {/\@token_auth_required\b/, "flask-security token_auth_required"},
    {/\@permission_required\s*\(/, "flask-security/principal permission_required"},
    {/\@auth\.login_required/, "flask-httpauth login_required"},
    {/\@auth\.verify_password/, "flask-httpauth verify_password"},
    {/\@token_auth\.login_required/, "flask-httpauth token_auth"},
    {/\@multi_auth\.login_required/, "flask-httpauth multi_auth"},
    {/\@requires_auth/, "requires_auth"},
    {/\@authenticated/, "authenticated"},
  ]

  def self.target_techs : Array(String)
    ["python_flask"]
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walk below with IndexError.
      next if line_num < 1 || line_num > lines.size

      # The line is normally the `@app.route` decorator itself. Flask
      # registers whatever function the route decorator receives, so only
      # the decorators *below* it wrap the registered view: `@login_required`
      # above `@app.route` leaves the route open (Flask's docs say the route
      # decorator must be outermost). Read the stack below and nothing above.
      route_idx = line_num - 1
      if lines[route_idx].strip.starts_with?('@')
        annotation_lines_below(lines, route_idx, "@").each do |current|
          if desc = decorator_description(current)
            endpoint.add_tag(Tag.new("auth", "Protected by #{desc}", "flask_auth"))
            return
          end
        end
        next
      end

      # Otherwise the line is the view itself: walk back over its decorators.
      # 8-line window: Flask decorators stack above def, typically 1-5 decorators
      idx = line_num - 2 # 0-indexed, one line before
      while idx >= 0 && idx >= line_num - 10
        current = lines[idx].strip
        break if current.empty? && idx < line_num - 2

        if desc = decorator_description(current)
          endpoint.add_tag(Tag.new("auth", "Protected by #{desc}", "flask_auth"))
          return
        end

        idx -= 1
      end
    end
  end

  private def decorator_description(line : String) : String?
    DECORATOR_PATTERNS.each do |pattern, desc|
      return desc if line.matches?(pattern)
    end
    nil
  end
end
