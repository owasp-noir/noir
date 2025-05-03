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
      target_paths = analyze_android_manifest(client)


      Fiber.yield
      @result
    end

    private def analyze_android_manifest(client : LLM::General) : Hash(String, JSON::Any)
      locator = CodeLocator.instance
      all_paths = locator.all("file_map")
      result = {} of String => JSON::Any

      all_paths.each do |path|
        if path.ends_with?("AndroidManifest.xml")
          logger.debug_sub "AI::Analyzing #{path}"
          xml_content = File.read(path, encoding: "utf-8", invalid: :skip)
          exported_components = extract_exported_components(xml_content)
          logger.debug_sub exported_components
          prompt = "#{LLM::ANDROID_MANIFEST_PROMPT}\n#{exported_components}"
          response = client.request(prompt, LLM::ANDROID_MANIFEST_FORMAT)
          logger.debug_sub response
          if response
            result[path] = JSON.parse(response.to_s)
          end
        end
      end

      result
    end

    def extract_exported_components(xml_string : String) : String
      components = [] of String
      reader = XML::Reader.new(xml_string)
    
      component_types = ["activity", "service", "provider", "receiver"]
      current_component = nil
      is_exported = false
      current_element = nil
    
      while reader.read
        case reader.node_type
        when XML::Reader::Type::ELEMENT
          name = reader.name
          if component_types.includes?(name)
            current_component = name
            current_element = reader.read_outer_xml
            exported_attr = reader["android:exported"]?
            is_exported = exported_attr == "true"
            if is_exported
              components << current_element
            end
          end
        end
      end
    
      "<manifest>\n#{components.join("")}\n</manifest>"
    end
  end
end
