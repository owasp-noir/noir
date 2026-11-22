require "./ts_dto_module"
require "./js_handler_resolver"

module Noir
  # Resolves only symbols visible from the handler. Parsed modules are shared
  # across scan workers, while recursion guards belong to one lookup.
  class TsDtoResolver
    alias Symbol = Tuple(String, String)

    TYPE_NAME = /\A[\w$]+(?:\.[\w$]+)*\z/

    @modules = {} of String => TsDtoModule
    @mutex = Mutex.new

    def initialize(&@read : String -> String)
    end

    def fields(type : String, path : String) : Array(String)?
      type = type.strip
      active = Set(Symbol).new
      memo = {} of Symbol => Array(String)
      return expand(path, type, active, memo) if type.matches?(TYPE_NAME)

      # Parse a complex annotation with the same rules as a named type alias.
      # In particular, a union of two generic types is not its first member.
      shape = TsDtoModule.parse("type Request = #{type}", "annotation.ts").declarations["Request"]? || return
      fields_for_shape(shape, path, active, memo)
    rescue
      nil
    end

    private def read_module(path : String) : TsDtoModule
      cached = @mutex.synchronize { @modules[path]? }
      return cached if cached
      parsed = begin
        TsDtoModule.parse(@read.call(path), path)
      rescue
        TsDtoModule.new
      end
      @mutex.synchronize { @modules[path] = parsed }
    end

    private def expand(path : String, name : String, active : Set(Symbol), memo : Hash(Symbol, Array(String))) : Array(String)?
      file, local = local_symbol(path, name, Set(Symbol).new) || return
      key = {file, local}
      if cached = memo[key]?
        return cached
      end
      return if active.size >= 64 || !active.add?(key)
      begin
        shape = read_module(file).declarations[local]? || return
        fields = fields_for_shape(shape, file, active, memo) || return
        memo[key] = fields
      ensure
        active.delete(key)
      end
    end

    private def fields_for_shape(shape : TsDtoModule::Shape, file : String, active : Set(Symbol), memo : Hash(Symbol, Array(String))) : Array(String)?
      shape.wrappers.each do |wrapper|
        target, fn = local_symbol(file, wrapper.name, Set(Symbol).new) || return
        return unless read_module(target).wrappers[fn]? == wrapper.raw_shape
      end
      fields = shape.fields.dup
      shape.bases.each do |base|
        inherited = expand(file, base.name, active, memo) || return
        if pick = base.pick
          inherited &= pick
        end
        fields |= inherited - base.omit
      end
      fields
    end

    private def local_symbol(path : String, name : String, visited : Set(Symbol)) : Symbol?
      table = read_module(path)
      return {path, name} if table.declarations.has_key?(name) || table.wrappers.has_key?(name)
      root, _, member = name.partition('.')
      binding = table.imports[root]? || return
      target = binding.source.try { |src| JSHandlerResolver.resolve_specifier(path, src) } || return
      if binding.name == "*"
        return if member.empty?
        exported_symbol(target, member, visited)
      elsif member.empty?
        exported_symbol(target, binding.name, visited)
      end
    end

    private def exported_symbol(path : String, name : String, visited : Set(Symbol)) : Symbol?
      key = {path, name}
      return if visited.size >= 64 || !visited.add?(key)
      table = read_module(path)
      if binding = table.exports[name]?
        source = binding.source || return local_symbol(path, binding.name, visited)
        target = JSHandlerResolver.resolve_specifier(path, source) || return
        return exported_symbol(target, binding.name, visited)
      end
      return if name == "default"
      found = nil.as(Symbol?)
      table.stars.each do |source|
        target = JSHandlerResolver.resolve_specifier(path, source) || next
        symbol = exported_symbol(target, name, visited) || next
        return if found && found != symbol
        found = symbol
      end
      found
    end
  end
end
