require "../ext/tree_sitter/tree_sitter"

# Immediate assignments in Python module and class suites. Keep RHS expressions
# intact so consumers can distinguish literals, calls and unresolved references.
module Noir::PythonDeclarations
  class Scope
    getter attributes = {} of String => String
    getter classes = {} of String => Scope
    getter methods = {} of String => String
    getter bases : String

    def initialize(@bases = "")
    end

    # Read the named field on the constructed settings class. An ordinary
    # class literal is exact; a BaseSettings literal is an environment default.
    def class_environment_default(class_name : String, field : String) : String?
      klass = classes[class_name]? || return
      rhs = klass.attributes[field]? || return
      environment_value(rhs) ||
        (PythonDeclarations.settings_default(rhs) if klass.bases.matches?(/\bBaseSettings\b/))
    end

    def environment_attribute(expression : String, module_member : Bool) : String?
      owner, _, field = expression.rpartition('.')
      if constructor = attributes[owner]?
        klass = constructor.match(/\A(\w+)\(\s*\)\z/) || return
        return class_environment_default(klass[1], field)
      end
      return unless owner.empty? || module_member
      rhs = attributes[field]? || field
      environment_value(rhs)
    end

    private def environment_value(rhs : String) : String?
      if method = methods[rhs.rchop("()")]?
        return unless rhs.ends_with?("()")
        returns = PythonDeclarations.reachable_values(method, ->(_guard : String) { nil.as(Bool?) })
        return unless returns.size == 1
        rhs = returns.first
      end
      PythonDeclarations.environment_default(rhs)
    end
  end

  # A default is evidence about the path on an unconfigured deployment.
  # A lookup without a string default supplies no such evidence.
  def self.environment_default(rhs : String) : String?
    rhs.match(/\Aos\.(?:getenv|environ\.get)\(\s*(["'])[^"']+\1\s*,\s*(?:default\s*=\s*)?(["'])([^"'\\]*)\2\s*\)\z/).try(&.[3])
  end

  def self.settings_default(rhs : String) : String?
    rhs.match(/\A(["'])([^"'\\]*)\1\z/).try(&.[2]) ||
      rhs.match(/\A(?:pydantic\.)?Field\(\s*(?:default\s*=\s*)?(["'])([^"'\\]*)\1\s*(?:,|\))/).try(&.[2])
  end

  def self.parse(source : String) : Scope
    scope = Scope.new
    TreeSitter.parse_python(source) { |root| collect(root, source, scope) }
    scope
  rescue
    # An unavailable syntax tree must not prevent URLconf analysis. The
    # consumer can still use the original line-based declaration index.
    Scope.new
  end

  private def self.collect(body, source : String, scope : Scope)
    TreeSitter.each_named_child(body) do |statement|
      node = TreeSitter.field(statement, "definition") || statement
      case TreeSitter.node_type(node)
      when "class_definition"
        name = TreeSitter.field(node, "name") || next
        suite = TreeSitter.field(node, "body") || next
        bases = TreeSitter.field(node, "superclasses").try { |args| TreeSitter.node_text(args, source) }
        klass = Scope.new(bases.to_s)
        scope.classes[TreeSitter.node_text(name, source)] = klass
        collect(suite, source, klass)
      when "function_definition"
        name = TreeSitter.field(node, "name") || next
        scope.methods[TreeSitter.node_text(name, source)] = TreeSitter.node_text(node, source)
      when "with_statement"
        # A context manager does not introduce a new Python namespace.
        TreeSitter.field(node, "body").try { |suite| collect(suite, source, scope) }
      when "expression_statement"
        assignment = TreeSitter.first_named_child(node) || next
        next unless TreeSitter.node_type(assignment) == "assignment"
        left = TreeSitter.field(assignment, "left") || next
        right = TreeSitter.field(assignment, "right") || next
        next unless TreeSitter.node_type(left) == "identifier"
        scope.attributes[TreeSitter.node_text(left, source)] = TreeSitter.node_text(right, source)
      end
    end
  end

  # Return expressions on reachable branches. The caller can evaluate guards
  # it knows; an unknown guard leaves both branches reachable.
  def self.reachable_values(source : String, guard : Proc(String, Bool?), assignment : String? = nil) : Array(String)
    values = [] of String
    TreeSitter.parse_python(source) do |root|
      method = TreeSitter.first_named_child(root) || next
      body = TreeSitter.field(method, "body") || next
      collect_values(body, source, guard, assignment, values)
    end
    values.uniq
  rescue
    [] of String
  end

  private def self.collect_values(block, source, guard, assignment, values) : Bool
    TreeSitter.each_named_child(block) do |node|
      case TreeSitter.node_type(node)
      when "return_statement"
        TreeSitter.first_named_child(node).try { |expr| values << TreeSitter.node_text(expr, source) } unless assignment
        return true
      when "expression_statement"
        next unless assignment
        binding = TreeSitter.first_named_child(node) || next
        left = TreeSitter.field(binding, "left") || next
        next unless TreeSitter.node_text(left, source) == assignment
        TreeSitter.field(binding, "right").try { |expr| values << TreeSitter.node_text(expr, source) }
      when "raise_statement"
        return true
      when "if_statement"
        clauses = [node]
        TreeSitter.each_named_child(node) do |child|
          clauses << child if TreeSitter.node_type(child).in?("elif_clause", "else_clause")
        end
        falls_through = false
        clauses.each do |clause|
          suite = TreeSitter.field(clause, "consequence") || TreeSitter.field(clause, "body") || next
          condition = TreeSitter.field(clause, "condition")
          applies = condition ? guard.call(TreeSitter.node_text(condition, source)) : true
          next if applies == false
          falls_through = true unless collect_values(suite, source, guard, assignment, values)
          if applies
            return true unless falls_through
            break
          end
        end
      end
    end
    false
  end
end
