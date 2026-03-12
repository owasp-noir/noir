require "../../../models/framework_tagger"
require "../../../models/endpoint"

class DjangoAuthTagger < FrameworkTagger
  DECORATOR_PATTERNS = [
    /\@login_required/,
    /\@permission_required\s*\(/,
    /\@user_passes_test\s*\(/,
    /\@staff_member_required/,
  ]

  MIXIN_PATTERNS = [
    /LoginRequiredMixin/,
    /PermissionRequiredMixin/,
    /UserPassesTestMixin/,
    /StaffMemberRequiredMixin/,
  ]

  DRF_PATTERNS = [
    /permission_classes\s*=\s*\[.*IsAuthenticated/,
    /permission_classes\s*=\s*\[.*IsAdminUser/,
    /permission_classes\s*=\s*\[.*DjangoModelPermissions/,
    /permission_classes\s*=\s*\(.*IsAuthenticated/,
    /permission_classes\s*=\s*\(.*IsAdminUser/,
    /permission_classes\s*=\s*\(.*DjangoModelPermissions/,
  ]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "django_auth"
  end

  def self.target_techs : Array(String)
    ["python_django"]
  end

  def perform(endpoints : Array(Endpoint)) : Array(Endpoint)
    endpoints.each do |endpoint|
      check_endpoint(endpoint)
    end

    endpoints
  end

  private def check_endpoint(endpoint : Endpoint)
    contexts = read_source_context(endpoint, 30)
    return if contexts.empty?

    contexts.each do |ctx|
      line = ctx.line
      lines = ctx.full_content.split("\n")

      if line
        # Check decorators by walking backwards from endpoint line
        description = check_decorators(lines, line)
        if description
          endpoint.add_tag(Tag.new("auth", description, "django_auth"))
          return
        end

        # Check enclosing class for mixins
        description = check_enclosing_class_mixins(lines, line)
        if description
          endpoint.add_tag(Tag.new("auth", description, "django_auth"))
          return
        end

        # Check enclosing class for DRF permission_classes
        description = check_enclosing_class_drf(lines, line)
        if description
          endpoint.add_tag(Tag.new("auth", description, "django_auth"))
          return
        end
      end
    end
  end

  private def check_decorators(lines : Array(String), endpoint_line : Int32) : String?
    # Walk backwards with no fixed limit — Python decorators stack directly above the def,
    # separated only by other decorators, so we stop at the first blank line or definition.
    idx = endpoint_line - 2 # 0-indexed, one line before
    return if idx < 0

    while idx >= 0
      current = lines[idx].strip
      # Stop at blank lines or other definitions
      break if current.empty?
      break if current.starts_with?("class ") || (current.starts_with?("def ") && idx < endpoint_line - 2)

      DECORATOR_PATTERNS.each do |pattern|
        if current.matches?(pattern)
          decorator_name = current.split("(").first.lstrip('@')
          return "Protected by Django #{decorator_name} decorator"
        end
      end

      idx -= 1
    end

    nil
  end

  private def check_enclosing_class_mixins(lines : Array(String), endpoint_line : Int32) : String?
    # Walk backwards from endpoint line to find the enclosing class definition
    idx = endpoint_line - 1 # 0-indexed
    while idx >= 0
      current = lines[idx].lstrip
      if current.starts_with?("class ") && current.includes?("(")
        # Found the enclosing class — check for mixins
        MIXIN_PATTERNS.each do |pattern|
          if current.matches?(pattern)
            mixin_name = pattern.source.gsub("\\", "")
            return "Protected by Django #{mixin_name}"
          end
        end
        # Found a class but no mixin — stop searching
        return
      end
      # If we hit a top-level def (not indented), we're not in a class
      if current.starts_with?("def ") && lines[idx] == lines[idx].lstrip
        return
      end
      idx -= 1
    end

    nil
  end

  private def check_enclosing_class_drf(lines : Array(String), endpoint_line : Int32) : String?
    # Walk backwards from endpoint line to find permission_classes in same class
    idx = endpoint_line - 1 # 0-indexed
    while idx >= 0
      current = lines[idx].lstrip
      # If we hit the class definition, stop
      if current.starts_with?("class ")
        return
      end
      # If we hit a top-level def (not indented), we're not in a class
      if current.starts_with?("def ") && lines[idx] == lines[idx].lstrip
        return
      end

      DRF_PATTERNS.each do |pattern|
        if current.matches?(pattern)
          return "Protected by DRF permission_classes"
        end
      end

      idx -= 1
    end

    nil
  end
end
