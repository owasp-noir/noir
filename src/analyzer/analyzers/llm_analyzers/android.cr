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
  class Android < Analyzer
    @llm_url : String
    @model : String
    @api_key : String?
    @max_tokens : Int32

    private EXCLUDED_DIRS       = ["/test", "/androidTest", "/generated/"]
    private COMPONENT_TYPES     = ["activity", "activity-alias", "service"]
    private FILE_EXTENSIONS     = [".java", ".kt"]
    private FILE_CONTENT_CACHE  = {} of String => String

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

      package_name, manifest_components = get_exported_components()
      
      manifest_components.each do |manifest_path, components|
        logger.debug "Processing manifest: #{manifest_path}"
        components.each do |component_name, data|
          # Process the component data
          component_data = data.as_h
          
          # Extract arrays of actions, categories, and data schemes
          actions = component_data["actions"].as_a.map(&.as_s)
          categories = component_data["categories"].as_a.map(&.as_s)
          data_infos = component_data["data_infos"].as_a.map(&.as(JSON::Any))
          
          # Generate all possible intent URLs
          intent_urls = [] of String
          
          # If no actions or categories, add an empty one to ensure we generate at least one URL
          actions = [""] of String if actions.empty?
          categories = [""] of String if categories.empty?
          data_infos = [JSON::Any.new({} of String => JSON::Any)] of JSON::Any if data_infos.empty?
          
          # Generate all combinations
          actions.each do |action|
            categories.each do |category|
              data_infos.each do |data_info|
                host_path = ""

                if data_info["host"]? != nil
                  host = data_info["host"].as_s
                  host_path = host
                end
                if data_info["path"]? != nil
                  path = data_info["path"].as_s
                  unless path.starts_with?("/")
                    path = "/#{path}"
                  end
                  host_path = "#{host_path}#{path}"
                elsif data_info["pathPrefix"]? != nil
                  path_prefix = data_info["pathPrefix"].as_s
                  unless path_prefix.starts_with?("/")
                    path_prefix = "/#{path_prefix}"
                  end
                  host_path = "#{host_path}#{path_prefix}"
                elsif data_info["pathPattern"]? != nil
                  path_pattern = data_info["pathPattern"].as_s
                  unless path_pattern.starts_with?("/")
                    path_pattern = "/#{path_pattern}"
                  end
                  host_path = "#{host_path}#{path_pattern}"
                end
                
                # Create intent URL in the format: intent://HOST/PATH#Intent;...;end;
                intent_url = "intent://" + host_path + "#Intent;"

                # Add scheme if available
                if data_info["scheme"]? != nil
                  scheme = data_info["scheme"].as_s
                  intent_url += "scheme=#{scheme};"
                end

                # Add mime type if available
                if data_info["mimeType"]? != nil
                  mime_type = data_info["mimeType"].as_s
                  intent_url += "type=#{mime_type};"
                end
                
                # Add action, category, and scheme if available
                intent_url += "action=#{action};" unless action.empty?
                intent_url += "category=#{category};" unless category.empty?
                
                # Add package if available
                intent_url += "package=#{package_name};" unless package_name.empty?
                
                # Add component
                if component_name.starts_with?(package_name)
                  intent_url += "component=#{component_name};"
                else
                  unless component_name.starts_with?(".")
                    component_name = ".#{component_name}"
                  end
                  intent_url += "component=#{package_name}#{component_name};"
                end
                
                # Close the intent URL
                intent_url += "end"
                
                intent_urls << intent_url
                logger.debug_sub "Generated intent URL: #{intent_url}"
              end
            end
          end
          #puts intent_urls
        end
      end
    
      Fiber.yield
      @result
    end

    private def get_exported_components()
      logger.debug "Getting exported components"

      locator = CodeLocator.instance
      all_paths = locator.all("file_map")
      package_name = ""

      logger.debug "Searching for AndroidManifest.xml files"
      manifest_components = {} of String => Hash(String, JSON::Any)
      
      all_paths.each do |path|
        next if EXCLUDED_DIRS.any? { |dir| path.includes?(dir) }

        if path.ends_with?("AndroidManifest.xml")
          logger.debug_sub "AI::Analyzing #{path}"
          xml_content = File.read(path, encoding: "utf-8", invalid: :skip)
          manifest = XML.parse(xml_content)
          
          components = {} of String => JSON::Any
          
          if root = manifest.root
            root.xpath_nodes("//*").each do |element|
              # Get the package name
              if package_name == "" && element.name.downcase == "manifest"
                package_name = element["package"]? || ""
              end

              # Check if this is a component element
              if COMPONENT_TYPES.includes?(element.name.downcase)
                exported_attr = element["exported"]?
                if exported_attr == "true"
                  logger.debug_sub "Found exported component: #{element.name}"
                  
                  # Get the component name from attributes
                  component_name = element["name"]?
                  if component_name
                    logger.debug_sub "Component name: #{component_name}"
                    
                    # Create a hash to store intent filter data for this component
                    component_data = {
                      "actions" => [] of JSON::Any,
                      "categories" => [] of JSON::Any,
                      "data_infos" => [] of JSON::Any,
                    }
                    
                    # Parse intent filters for this component
                    element.children.each do |child|
                      if child.is_a?(XML::Node) && child.name.downcase == "intent-filter"
                        logger.debug_sub "Found intent-filter for component: #{component_name}"
                        
                        # Process all children of the intent-filter
                        child.children.each do |intent_child|
                          if intent_child.is_a?(XML::Node)
                            case intent_child.name.downcase
                            when "action"
                              if action_name = intent_child["name"]?
                                component_data["actions"] << JSON::Any.new(action_name)
                                logger.debug_sub "  Action: #{action_name}"
                              end
                            when "category"
                              if category_name = intent_child["name"]?
                                component_data["categories"] << JSON::Any.new(category_name)
                                logger.debug_sub "  Category: #{category_name}"
                              end
                            when "data"
                              # Handle scheme, host, and path as a set
                              scheme_value = intent_child["scheme"]?
                              host_value = intent_child["host"]?
                              path_value = intent_child["path"]?
                              path_prefix_value = intent_child["pathPrefix"]?
                              path_pattern_value = intent_child["pathPattern"]?
                              mime_type_value = intent_child["mimeType"]?
                              data = {
                                "scheme" => JSON::Any.new(scheme_value || nil),
                                "host" => JSON::Any.new(host_value || nil),
                                "path" => JSON::Any.new(path_value || nil),
                                "pathPrefix" => JSON::Any.new(path_prefix_value || nil),
                                "pathPattern" => JSON::Any.new(path_pattern_value || nil),
                                "mimeType" => JSON::Any.new(mime_type_value || nil)
                              }
                              component_data["data_infos"] << JSON::Any.new(data)
                            end
                          end
                        end
                      end
                    end
                    
                    # Log the parsed intent filter data
                    if !component_data["actions"].empty? || !component_data["categories"].empty? || !component_data["data_infos"].empty?
                      logger.debug_sub "Intent filter data for #{component_name}:"
                      logger.debug_sub "  Actions: #{component_data["actions"].join(", ")}" unless component_data["actions"].empty?
                      logger.debug_sub "  Categories: #{component_data["categories"].join(", ")}" unless component_data["categories"].empty?
                      logger.debug_sub "  Schemes: #{component_data["data_infos"].join(", ")}" unless component_data["data_infos"].empty?
                    end
                    
                    # Map the component name to its intent filter data
                    components[component_name] = JSON.parse({
                      "actions" => component_data["actions"],
                      "categories" => component_data["categories"],
                      "data_infos" => component_data["data_infos"]
                    }.to_json)
                  end
                end
              end
            end
          end
          
          # Add components from this manifest to the result
          manifest_components[path] = components unless components.empty?
        end
      end
      
      raise "No package name found" if package_name == ""
      return package_name, manifest_components
    end
  end
end
