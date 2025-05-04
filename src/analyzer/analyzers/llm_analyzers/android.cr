require "../../../utils/utils.cr"
require "../../../models/analyzer"
require "../../../llm/general/client"
require "../../../llm/prompt"
require "xml"

module Analyzer::AI
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
    end

    def analyze
      client = LLM::General.new(@llm_url, @model, @api_key)
      manifest_analysis = analyze_manifest(client)
      
      manifest_analysis.each do |path, response|
        response.as_h.each do |key, value|
          case key
          when "package"
            logger.debug_sub "Package: #{value.as_s}"
          when "components"
            value.as_h.each do |component_type, components|
              logger.debug_sub "  #{component_type.capitalize}:"
              components.as_a.each do |component|
                logger.debug_sub "    #{component["name"].as_s}"
              end
            end
          end
        end
      end
        
      Fiber.yield
      @result
    end

    private def analyze_manifest(client : LLM::General) : Hash(String, JSON::Any)
      locator = CodeLocator.instance
      all_paths = locator.all("file_map")
      result = {} of String => JSON::Any

      all_paths.each do |path|
        next if path.includes?("/test/") || path.includes?("/tests/")
        if path.ends_with?("AndroidManifest.xml")
          logger.debug_sub "AI::Analyzing #{path}"
          xml_content = File.read(path, encoding: "utf-8", invalid: :skip)
          manifest_content = extract_manifest_content(xml_content)
          prompt = "#{LLM::ANDROID_MANIFEST_PROMPT}\n#{manifest_content}"
          response = client.request(prompt, LLM::ANDROID_MANIFEST_FORMAT)
          if response
            result[path] = JSON.parse(response.to_s)
            logger.debug_sub "AI::Result: #{result[path].to_s}"
          end
        end
      end

      result
    end

    def extract_manifest_content(xml_string : String) : String
      # Parse the entire manifest
      manifest = XML.parse(xml_string)

      # Get the root manifest element
      manifest_root = manifest.root

      # Define component types to check
      component_types = ["activity", "activity-alias", "service", "provider", "receiver"]
      # Find all components that are not exported and remove them
      component_types.each do |component_type|
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
      
      # Return the modified manifest as string
      manifest.to_s
    end
  end
end
