require "../../../models/framework_tagger"
require "../../../models/endpoint"

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

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "flask_auth"
  end

  def self.target_techs : Array(String)
    ["python_flask"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end
    endpoints
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      content = read_file(path_info.path)
      next if content.nil?

      lines = content.split("\n")
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walk below with IndexError.
      next if line_num < 1 || line_num > lines.size

      # Walk backwards from function definition to find decorators
      # 8-line window: Flask decorators stack above def, typically 1-5 decorators
      idx = line_num - 2 # 0-indexed, one line before
      while idx >= 0 && idx >= line_num - 10
        current = lines[idx].strip
        break if current.empty? && idx < line_num - 2

        DECORATOR_PATTERNS.each do |pattern, desc|
          if current.matches?(pattern)
            endpoint.add_tag(Tag.new("auth", "Protected by #{desc}", "flask_auth"))
            return
          end
        end

        idx -= 1
      end
    end
  end
end
