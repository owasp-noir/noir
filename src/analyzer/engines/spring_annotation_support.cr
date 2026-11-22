require "../../miniparsers/spring_annotation_index"

module Analyzer::Java::SpringAnnotationSupport
  @annotations = Noir::SpringAnnotationIndex.new

  private def index_spring_annotations(root, content, path)
    @annotations.add(root, content, path, configured_base_for(path), project_root_for(path))
  end

  # Controllers and mapping interfaces already contributed their route trees.
  # A plain base class or a custom annotation can live in either JVM language
  # without declaring any route. Only definitions the bindings reference need
  # a parse. The name gate selects candidate files; resolution uses their AST.
  private def resolve_spring_annotations
    return if @annotations.empty?
    candidates = Hash(String, Array(String)).new
    get_files_by_extensions([".java", ".kt"]).each do |path|
      next if @annotations.indexed?(path)
      relative = base_relative_path(path)
      next if path.ends_with?(".kt") ? Analyzer::Kotlin::KotlinEngine.test_path?(relative) : Analyzer::Java::JavaEngine.test_path?(relative)
      content = read_file_content(path)
      content.scan(/\b(?:class|interface|object)\s+([\w$]+)/) { |match| (candidates[match[1]] ||= [] of String) << path }
    end
    @annotations.resolve do |name|
      candidates.delete(name).try &.each do |path|
        @annotations.read(path, read_file_content(path), configured_base_for(path), project_root_for(path))
      rescue ex
        @logger.debug "Could not read Spring annotation definitions in #{path}: #{ex.message}"
      end
    end
  end
end
