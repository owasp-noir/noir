require "../../../models/framework_tagger"
require "../../../models/endpoint"

class PythonMiscAuthTagger < FrameworkTagger
  # Sanic auth patterns
  SANIC_PATTERNS = [
    {/\@authorized\s*\(/, "Sanic @authorized decorator"},
    {/\@protected\s*\(/, "Sanic @protected decorator"},
    {/\@scoped\s*\(/, "Sanic @scoped decorator"},
    {/sanic_jwt/, "Sanic JWT"},
    {/\@auth\.login_required/, "Sanic auth login_required"},
  ]

  # Tornado auth patterns
  TORNADO_PATTERNS = [
    {/\@tornado\.web\.authenticated/, "Tornado @authenticated decorator"},
    {/\@authenticated/, "Tornado @authenticated"},
    {/get_current_user\s*\(/, "Tornado get_current_user"},
    {/current_user/, "Tornado current_user check"},
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "python_misc_auth"
  end

  def self.target_techs : Array(String)
    ["python_sanic", "python_tornado"]
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
      line_idx = line_num - 1

      # Check decorators above function/method
      description = check_decorators(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "python_misc_auth"))
        return
      end

      # Check class for Tornado auth mixin/method
      description = check_class_auth(lines, line_idx)
      if description
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "python_misc_auth"))
        return
      end
    end
  end

  private def check_decorators(lines : Array(String), func_line : Int32) : String?
    idx = func_line - 1
    while idx >= 0 && idx >= func_line - 5
      current = lines[idx].strip
      break if current.empty? && idx < func_line - 1

      all_patterns = SANIC_PATTERNS + TORNADO_PATTERNS
      all_patterns.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end

      idx -= 1
    end
    nil
  end

  private def check_class_auth(lines : Array(String), method_line : Int32) : String?
    # Walk backwards to find class definition with Tornado's get_current_user override
    idx = method_line
    while idx >= 0
      current = lines[idx].strip

      if current.starts_with?("class ")
        # Found class — scan class body for get_current_user
        scan_idx = idx + 1
        while scan_idx < lines.size && scan_idx < idx + 30
          scan_line = lines[scan_idx].strip
          break if scan_line.starts_with?("class ")

          if scan_line.includes?("def get_current_user")
            return "Tornado get_current_user override"
          end

          scan_idx += 1
        end
        break
      end

      idx -= 1
    end
    nil
  end
end
