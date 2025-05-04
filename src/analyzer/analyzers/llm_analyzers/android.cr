require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "../../../llm/general/client"
require "../../../llm/prompt"
require "xml"
require "json"
require "../../../minilexers/java"
require "../../../miniparsers/java"
require "../../../minilexers/kotlin"
require "../../../miniparsers/kotlin"

module Analyzer::AI
  private EXCLUDED_DIRS       = ["/test/", "/tests/", "/androidTest/", "/generated/"]
  private COMPONENT_TYPES     = ["activity", "activity-alias", "service", "provider", "receiver"]
  private FILE_EXTENSIONS     = [".java", ".kt"]
  private FILE_CONTENT_CACHE  = {} of String => String

  class Android < Analyzer
    @llm_url : String
    @model : String
    @api_key : String?
    @max_tokens : Int32

    def initialize(options : Hash(String, YAML::Any))
      super(options)
      @llm_url = options["ai_provider"].as_s
      @model = options["ai_model"].as_s
      @api_key = options["ai_key"].as_s
      @max_tokens = LLM.get_max_tokens(@llm_url, @model)
      logger.debug "Android analyzer initialized with model: #{@model}"
    end

    def analyze
      client = LLM::General.new(@llm_url, @model, @api_key)
      logger.debug "Starting Android manifest analysis"
      manifest_analysis = analyze_manifest(client)
      package_name = nil
      components_data = nil
      manifest_path = nil
      
      manifest_analysis.each do |path, response|
        manifest_path = path
        logger.debug "Processing manifest at: #{path}"
        response.as_h.each do |key, value|
          case key
          when "package"
            package_name = value.as_s
            logger.debug_sub "Package: #{package_name}"
          when "components"
            components_data = value
            logger.debug_sub "Found components data"
          end
        end
      end

      # Fail if package name is not found
      unless package_name
        logger.error "Package name not found in manifest"
        return @result
      end

      # Process components if found
      if components_data && manifest_path
        logger.debug "Processing #{components_data.as_h.size} component types"
        components_data.as_h.each do |component_type, components|
          logger.debug_sub "  #{component_type.capitalize}:"
          components.as_a.each do |component|
            component_name = component["name"].as_s
            logger.debug_sub "    #{component_name}"
            
            # Check if it's an alias and get the target activity
            if component["is_alias"]?.try(&.as_bool)
              target_activity = component["target_activity"].as_s
              logger.debug_sub "    Alias target: #{target_activity}"
              analyze_component_file(target_activity, package_name.not_nil!, client, manifest_path, component)
            else
              analyze_component_file(component_name, package_name.not_nil!, client, manifest_path, component)
            end
          end
        end
      end
        
      Fiber.yield
      logger.debug "Android analysis complete with #{@result.size} endpoints"
      @result
    end

    private def analyze_manifest(client : LLM::General) : Hash(String, JSON::Any)
      locator = CodeLocator.instance
      all_paths = locator.all("file_map")
      result = {} of String => JSON::Any
      logger.debug "Searching for AndroidManifest.xml files"

      all_paths.each do |path|
        next if EXCLUDED_DIRS.any? { |dir| path.includes?(dir) }

        if path.ends_with?("AndroidManifest.xml")
          logger.debug_sub "AI::Analyzing #{path}"
          xml_content = File.read(path, encoding: "utf-8", invalid: :skip)
          manifest_content = extract_manifest_content(xml_content)
          logger.debug_sub "Manifest content extracted (#{manifest_content.size} bytes)"
          prompt = "#{LLM::ANDROID_MANIFEST_PROMPT}\n#{manifest_content}"
          logger.debug_sub "Sending manifest to LLM for analysis"
          response = client.request(prompt, LLM::ANDROID_MANIFEST_FORMAT)
          if response
            result[path] = JSON.parse(response.to_s)
            logger.debug_sub "AI::Result: #{result[path].to_s}"
          else
            logger.debug_sub "No response received from LLM for manifest"
          end
        end
      end

      logger.debug "Found #{result.size} manifest files"
      result
    end

    def extract_manifest_content(xml_string : String) : String
      logger.debug "Extracting manifest content"
      # Parse the entire manifest
      manifest = XML.parse(xml_string)

      # Get the root manifest element
      manifest_root = manifest.root

      # Find all components that are not exported and remove them
      COMPONENT_TYPES.each do |component_type|
        if manifest_root
          components_to_remove = [] of XML::Node
          manifest_root.xpath_nodes("//#{component_type}").each do |component|
            exported_attr = component["android:exported"]?
            # Only add to removal list if explicitly set to false
            # If not specified or set to anything else, keep the component
            if exported_attr == "false"
              components_to_remove << component
            end
          end

          # Remove XML comments to clean up the manifest
          if manifest_root
            comments_to_remove = [] of XML::Node
            manifest_root.xpath_nodes("//comment()").each do |comment|
              comments_to_remove << comment
            end

            comments_to_remove.each do |comment|
              comment.unlink
            end
          end

          # Remove empty lines and excessive whitespace to clean up the manifest
          if manifest_root
            text_nodes_to_remove = [] of XML::Node
            manifest_root.xpath_nodes("//text()").each do |text_node|
              # Check if the text node contains only whitespace
              if text_node.content.strip.empty?
                text_nodes_to_remove << text_node
              end
            end

            text_nodes_to_remove.each do |text_node|
              text_node.unlink
            end
          end

          # Remove components in a separate loop to avoid modifying during iteration
          components_to_remove.each do |component|
            if parent = component.parent
              component.unlink
            end
          end
        end
      end
      
      logger.debug "Manifest content extraction complete"
      # Return the modified manifest as string
      manifest.to_s
    end

    private def find_source_dirs(manifest_path : String) : Array(String)
      logger.debug "Finding source directories for #{manifest_path}"
      source_dirs = [] of String
      
      # Get the directory containing the manifest
      manifest_dir = File.dirname(manifest_path)
      
      # Try to find build.gradle files in parent directories
      current_dir = manifest_dir
      while current_dir != "/"
        build_files = [
          "#{current_dir}/build.gradle",
          "#{current_dir}/build.gradle.kts"
        ]

        build_files.each do |build_file|
          if File.exists?(build_file)
            logger.debug_sub "Found build file: #{build_file}"
            content = File.read(build_file)

            # Try to find sourceSet.main.java.srcDirs
            if content =~ /sourceSets\s*{\s*main\s*{\s*java\s*{\s*srcDirs\s*=\s*\[(.*?)\]\s*}/
              dirs = $1.split(",").map(&.strip.gsub(/['"]/, ""))
              source_dirs.concat(dirs)
              logger.debug_sub "Found sourceSets.main.java.srcDirs: #{dirs.join(", ")}"
            end

            # Try to find android.sourceSets.main.java.srcDirs
            if content =~ /android\s*{\s*sourceSets\s*{\s*main\s*{\s*java\s*{\s*srcDirs\s*=\s*\[(.*?)\]\s*}/
              dirs = $1.split(",").map(&.strip.gsub(/['"]/, ""))
              source_dirs.concat(dirs)
              logger.debug_sub "Found android.sourceSets.main.java.srcDirs: #{dirs.join(", ")}"
            end

            # Try to find kotlin.sourceSets.main.java.srcDirs
            if content =~ /kotlin\s*{\s*sourceSets\s*{\s*main\s*{\s*java\s*{\s*srcDirs\s*=\s*\[(.*?)\]\s*}/
              dirs = $1.split(",").map(&.strip.gsub(/['"]/, ""))
              source_dirs.concat(dirs)
              logger.debug_sub "Found kotlin.sourceSets.main.java.srcDirs: #{dirs.join(", ")}"
            end
          end
        end

        # Move up one directory
        current_dir = File.dirname(current_dir)
      end

      # Add default paths if no source directories found
      if source_dirs.empty?
        logger.debug_sub "No source directories found in build files, using defaults"
        # Get the relative path from manifest to project root
        relative_path = manifest_dir.split("/").select { |dir| dir != "app" && dir != "src" && dir != "main" && dir != "java" }
        
        # Android standard project structure
        source_dirs = [
          "src",                        # Alternative standard structure
          "src/main/java",               # Alternative standard structure
          "src/main/kotlin",             # Alternative Kotlin structure
          "app/src",                    # Standard Android Studio project
          "app/src/main/java",           # Standard Android Studio project
          "app/src/main/kotlin",         # Kotlin in Android Studio
          "app/src/release/java"         # Release source set
        ].map { |dir| relative_path.join("/") + "/" + dir }
      end

      logger.debug "Found #{source_dirs.size} source directories"
      source_dirs
    end

    private def analyze_component_file(component_name : String, package_name : String, client : LLM::General, manifest_path : String, component : JSON::Any)
      logger.debug "Analyzing component: #{component_name}"
      # Convert component name to file path
      parts = component_name.split(".")
      file_name = parts.pop # Get the last part as file name
      package_path = parts.join("/") # Join remaining parts as package path
      
      # Get source directories from Gradle build files relative to manifest
      source_dirs = find_source_dirs(manifest_path)
      
      # Generate possible paths
      possible_paths = FILE_EXTENSIONS.flat_map do |ext|
        source_dirs.map do |dir|
          "#{dir}/#{package_name.gsub(".", "/")}/#{package_path}/#{file_name}#{ext}"
        end
      end
      
      logger.debug_sub "Generated #{possible_paths.size} possible file paths"
      locator = CodeLocator.instance
      all_paths = locator.all("file_map")

      possible_paths.each do |path|
        resolved_path = Path[path].normalize
        if File.exists?(resolved_path)
          logger.debug_sub "    Found component file: #{resolved_path}"
          content = File.read(resolved_path, encoding: "utf-8", invalid: :skip)
          
          # Create parser based on file extension
          parser = resolved_path.to_s.ends_with?(".kt") ? 
                   create_kotlin_parser(resolved_path, content) : 
                   create_java_parser(resolved_path, content)
          
          # Bundle all imported files
          source_dir = resolved_path.to_s.split("#{package_path}/#{file_name}").first
          logger.debug_sub "    Bundling imported files from source dir: #{source_dir}"
          bundles = bundle_import_files(client, parser, resolved_path.to_s, source_dir)
          
          # Process each bundle
          bundles.each_with_index do |bundle_content, index|
            logger.debug_sub "    Processing bundle #{index + 1}/#{bundles.size}"
            
            # Analyze the file for Intent parameters
            logger.debug_sub "    Sending component file to LLM for analysis"
            prompt = <<-PROMPT
            Analyze the following Android component file to extract Intent parameters and their types.
            Focus on:
            - Intent extras in getIntent().getExtras()
            - Intent parameters in onNewIntent()
            - Intent parameters in startActivity() or startActivityForResult()
            - Bundle parameters that might contain Intent data
            - Look for variable references when intent parameter names are not string literals
            - Track variable assignments to determine actual parameter names
            - If you cannot determine the variable name, you may omit it
            
            Component object:
            #{component.to_s}
            
            File contents:
            #{content}
            
            Imported files bundle:
            #{bundle_content}
            PROMPT

            response = client.request(prompt, INTENT_PARAMETERS_FORMAT)
            logger.debug_sub "    AI::Response: #{response.to_s}"
            if response
              intent_params = JSON.parse(response.to_s)
              create_endpoint_from_intent(component_name, intent_params, component)
            else
              logger.debug_sub "    No response received from LLM for component analysis"
            end
          end
          break
        end
      end
    end

    private def bundle_import_files(client : LLM::General, parser : JavaParser | KotlinParser, current_file : String, source_dir : String) : Array(String)
      logger.debug "Bundling import files for #{current_file}"
      files_to_bundle = [] of Tuple(String, String)
      processed_files = Set(String).new
      files_to_process = [current_file] of String
      
      # Use a smaller token limit to account for model's context length
      token_limit = 3000 # Leave room for prompt and response
      
      while files_to_process.any?
        file_path = files_to_process.shift
        next if processed_files.includes?(file_path)
        processed_files.add(file_path)
        
        # Get file content
        content = fetch_file_content(file_path)
        
        # Create parser for the file
        file_parser = file_path.ends_with?(".kt") ? 
          create_kotlin_parser(Path.new(file_path), content) : 
          create_java_parser(Path.new(file_path), content)
        
        # Add file content to bundle
        if file_path != current_file
          files_to_bundle << {file_path, content}
        end
        
        # Get imports based on parser type
        imports = case file_parser
        when JavaParser
          file_parser.import_statements
        when KotlinParser
          file_parser.import_statements
        else
          [] of String
        end

        logger.debug_sub "Processing #{imports.size} imports from #{file_path}"
        current_bundle_map = Hash(String, String).new
        process_imports(imports, source_dir, file_path, current_bundle_map)
        current_bundle_map.each do |key, value|
          files_to_bundle << {key, value}
        end
        
        # Add files to processing queue
        add_files_to_processing_queue(imports, source_dir, processed_files, files_to_process)
      end

      # Bundle files considering token limits
      bundles = LLM.bundle_files(files_to_bundle, token_limit)
      logger.debug_sub "Created #{bundles.size} bundles for #{files_to_bundle.size} files"
      
      # Return all bundle contents
      bundles.map(&.first)
    end
    
    private def process_imports(imports : Array(String), source_dir : String, file_path : String, current_bundle_map : Hash(String, String))
      logger.debug "Processing imports for #{file_path}"
      FILE_EXTENSIONS.each do |ext|
        # Process each import statement
        imports.each do |import_statement|
          import_path = import_statement.gsub(".", "/")
          
          if import_path.ends_with?("/*")
            process_wildcard_import(import_path, source_dir, ext, current_bundle_map)
          else
            process_single_import(import_path, source_dir, ext, current_bundle_map)
          end
        end
        
        # Import packages from the same directory
        process_same_directory_imports(file_path, ext, current_bundle_map)
      end
    end
    
    private def process_wildcard_import(import_path : String, source_dir : String, ext : String, current_bundle_map : Hash(String, String))
      import_directory = Path[source_dir].join(import_path[..-3])
      logger.debug "Processing wildcard import: #{import_path} in directory: #{import_directory}"
      if Dir.exists?(import_directory)
        Dir.glob("#{import_directory}/*#{ext}") do |_path|
          next if current_bundle_map.has_key?(_path)
          current_bundle_map[_path] = fetch_file_content(_path)
          logger.debug_sub "Added wildcard import file: #{_path}"
        end
      end
    end
    
    private def process_single_import(import_path : String, source_dir : String, ext : String, current_bundle_map : Hash(String, String))
      source_path = Path[source_dir].join(import_path + ext)
      return if current_bundle_map.has_key?(source_path.to_s)
      
      logger.debug "Processing single import: #{import_path} -> #{source_path}"
      if File.exists?(source_path)
        current_bundle_map[source_path.to_s] = fetch_file_content(source_path.to_s)
        logger.debug_sub "Added single import file: #{source_path}"
      end
    end
    
    private def process_same_directory_imports(file_path : String, ext : String, current_bundle_map : Hash(String, String))
      file_directory = Path[file_path].dirname
      logger.debug "Processing same directory imports for: #{file_directory}"
      Dir.glob("#{file_directory}/*#{ext}") do |_path|
        next if current_bundle_map.has_key?(_path)
        current_bundle_map[_path] = fetch_file_content(_path)
        logger.debug_sub "Added same directory file: #{_path}"
      end
    end
    
    private def add_files_to_processing_queue(imports : Array(String), source_dir : String, processed_files : Set(String), files_to_process : Array(String))
      logger.debug "Adding files to processing queue"
      imports.each do |import_path|
        # Convert import path to file path
        import_file = import_path.gsub(".", "/")
        
        possible_paths = FILE_EXTENSIONS.flat_map do |ext|
          "#{source_dir}/#{import_file}#{ext}"
        end
        
        # Add found files to processing queue
        possible_paths.each do |path|
          if File.exists?(path) && !processed_files.includes?(path)
            files_to_process << path
            logger.debug_sub "Added to processing queue: #{path}"
          end
        end
      end
    end

    private def fetch_file_content(path : String) : String
      if FILE_CONTENT_CACHE.has_key?(path)
        logger.debug "Using cached file content for: #{path}"
        FILE_CONTENT_CACHE[path]
      else
        logger.debug "Reading file content for: #{path}"
        FILE_CONTENT_CACHE[path] = File.read(path, encoding: "utf-8", invalid: :skip)
      end
    end

    private def create_java_parser(path : Path, content : String = "") : JavaParser
      logger.debug "Creating Java parser for: #{path}"
      content = fetch_file_content(path.to_s) if content.empty?
      lexer = JavaLexer.new
      tokens = lexer.tokenize(content)
      JavaParser.new(path.to_s, tokens)
    end

    private def create_kotlin_parser(path : Path, content : String = "") : KotlinParser
      logger.debug "Creating Kotlin parser for: #{path}"
      content = fetch_file_content(path.to_s) if content.empty?
      lexer = KotlinLexer.new
      tokens = lexer.tokenize(content)
      KotlinParser.new(path.to_s, tokens)
    end

    private def create_endpoint_from_intent(component_name : String, intent_params : JSON::Any, component : JSON::Any)
      logger.debug "Creating endpoint from intent for: #{component_name}"
      # Create a new endpoint for the component
      endpoint = Endpoint.new(
        url: "android://#{component_name}",
        method: "INTENT"
      )

      # Add parameters from intent analysis
      if intent_params.as_h.has_key?("parameters")
        logger.debug_sub "Processing #{intent_params.as_h["parameters"].as_a.size} intent parameters"
        intent_params.as_h["parameters"].as_a.each do |param|
          param_name = param["name"].as_s
          param_type = param["type"].as_s
          
          param_obj = Param.new(
            name: param_name,
            value: param_type,
            param_type: "intent"
          )
          endpoint.push_param(param_obj)
          logger.debug_sub "Added parameter: #{param_name} (#{param_type})"
        end
      end

      # Add the endpoint to results
      @result << endpoint
      
      logger.debug_sub "    Created endpoint: #{endpoint.url} with #{endpoint.params.size} parameters"
    end

    INTENT_PARAMETERS_FORMAT = <<-FORMAT
    {
      "type": "json_schema",
      "json_schema": {
        "name": "intent_parameters",
        "schema": {
          "type": "object",
          "properties": {
            "parameters": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "name": { "type": "string" },
                  "type": { "type": "string" }
                },
                "required": ["name", "type"],
                "additionalProperties": false
              }
            }
          },
          "required": ["parameters"],
          "additionalProperties": false
        },
        "strict": true
      }
    }
    FORMAT
  end
end