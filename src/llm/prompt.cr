module LLM
  FILTER_PROMPT = <<-PROMPT
  Analyze the following list of file paths and identify which files are likely to represent endpoints, including API endpoints, web pages, or static resources.

  Guidelines:
  - Focus only on individual files.
  - Do not include directories.
  - Do not include any explanations, comments, or additional text.
  - Output only the JSON result.
  - Return the result strictly in valid JSON format according to the schema provided below.

  Input Files:
  PROMPT

  FILTER_FORMAT = <<-FORMAT
  {
    "type": "json_schema",
    "json_schema": {
      "name": "filter_files",
      "schema": {
        "type": "object",
        "properties": {
          "files": {
            "type": "array",
            "items": {
              "type": "string"
            }
          }
        },
        "required": ["files"],
        "additionalProperties": false
      },
      "strict": true
    }
  }
  FORMAT

  ANALYZE_PROMPT = <<-PROMPT
  Analyze the provided source code to extract details about the endpoints and their parameters.

  Guidelines:
  - The "method" field should strictly use one of these values: "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD".
  - The "param_type" must strictly use one of these values: "query", "json", "form", "header", "cookie", "path".
  - Do not include any explanations, comments, or additional text.
  - Output only the JSON result.
  - Return the result strictly in valid JSON format according to the schema provided below.

  Input Code:
  PROMPT

  ANALYZE_FORMAT = <<-FORMAT
  {
    "type": "json_schema",
    "json_schema": {
      "name": "analyze_endpoints",
      "schema": {
        "type": "object",
        "properties": {
          "endpoints": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "url": {
                  "type": "string"
                },
                "method": {
                  "type": "string"
                },
                "params": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "name": {
                        "type": "string"
                      },
                      "param_type": {
                        "type": "string"
                      },
                      "value": {
                        "type": "string"
                      }
                    },
                    "required": ["name", "param_type", "value"],
                    "additionalProperties": false
                  }
                }
              },
              "required": ["url", "method", "params"],
              "additionalProperties": false
            }
          }
        },
        "required": ["endpoints"],
        "additionalProperties": false
      },
      "strict": true
    }
  }
  FORMAT

  BUNDLE_ANALYZE_PROMPT = <<-PROMPT
  Analyze the following bundle of source code files to extract details about the endpoints and their parameters.

  Guidelines:
  - The "method" field should strictly use one of these values: "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD".
  - The "param_type" must strictly use one of these values: "query", "json", "form", "header", "cookie", "path".
  - Include endpoints from ALL files in the bundle.
  - Do not include any explanations, comments, or additional text.
  - Output only the JSON result.
  - Return the result strictly in valid JSON format according to the schema provided below.

  Bundle of files:
  PROMPT

  # Android Manifest Prompt
  ANDROID_MANIFEST_PROMPT = <<-PROMPT
  Analyze the provided AndroidManifest.xml file to extract details about the endpoints and their parameters.

  Guidelines:
  - Extract all the exported activities, services, and receivers from the AndroidManifest.xml file.
  - Output only the JSON result.
  - Return the result strictly in valid JSON format according to the schema provided below.

  Input AndroidManifest.xml:
  PROMPT

  ANDROID_MANIFEST_FORMAT = <<-FORMAT
  {
    "type": "json_schema",
    "json_schema": {
      "name": "android_manifest",
      "schema": {
        "type": "object",
        "properties": {
          "activities": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "name": { "type": "string" },
                "exported": { "type": "boolean" },
                "permission": { "type": "string" },
                "intent_filters": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "actions": {
                        "type": "array",
                        "items": { "type": "string" }
                      },
                      "categories": {
                        "type": "array",
                        "items": { "type": "string" }
                      },
                      "data": {
                        "type": "array",
                        "items": {
                          "type": "object",
                          "properties": {
                            "scheme": { "type": "string" },
                            "host": { "type": "string" },
                            "path": { "type": "string" },
                            "pathPattern": { "type": "string" },
                            "mimeType": { "type": "string" }
                          },
                          "required": ["scheme", "host", "path", "pathPattern", "mimeType"],
                          "additionalProperties": false
                        }
                      }
                    },
                    "required": ["actions", "categories", "data"],
                    "additionalProperties": false
                  }
                }
              },
              "required": ["name", "exported", "permission", "intent_filters"],
              "additionalProperties": false
            }
          },
          "services": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "name": { "type": "string" },
                "exported": { "type": "boolean" },
                "permission": { "type": "string" },
                "intent_filters": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "actions": {
                        "type": "array",
                        "items": { "type": "string" }
                      },
                      "categories": {
                        "type": "array",
                        "items": { "type": "string" }
                      },
                      "data": {
                        "type": "array",
                        "items": {
                          "type": "object",
                          "properties": {
                            "scheme": { "type": "string" },
                            "host": { "type": "string" },
                            "path": { "type": "string" },
                            "pathPattern": { "type": "string" },
                            "mimeType": { "type": "string" }
                          },
                          "required": ["scheme", "host", "path", "pathPattern", "mimeType"],
                          "additionalProperties": false
                        }
                      }
                    },
                    "required": ["actions", "categories", "data"],
                    "additionalProperties": false
                  }
                }
              },
              "required": ["name", "exported", "permission", "intent_filters"],
              "additionalProperties": false
            }
          },
          "receivers": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "name": { "type": "string" },
                "exported": { "type": "boolean" },
                "permission": { "type": "string" },
                "intent_filters": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "actions": {
                        "type": "array",
                        "items": { "type": "string" }
                      },
                      "categories": {
                        "type": "array",
                        "items": { "type": "string" }
                      },
                      "data": {
                        "type": "array",
                        "items": {
                          "type": "object",
                          "properties": {
                            "scheme": { "type": "string" },
                            "host": { "type": "string" },
                            "path": { "type": "string" },
                            "pathPattern": { "type": "string" },
                            "mimeType": { "type": "string" }
                          },
                          "required": ["scheme", "host", "path", "pathPattern", "mimeType"],
                          "additionalProperties": false
                        }
                      }
                    },
                    "required": ["actions", "categories", "data"],
                    "additionalProperties": false
                  }
                }
              },
              "required": ["name", "exported", "permission", "intent_filters"],
              "additionalProperties": false
            }
          },
          "providers": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "name": { "type": "string" },
                "authorities": { "type": "string" },
                "exported": { "type": "boolean" },
                "permission": { "type": "string" },
                "readPermission": { "type": "string" },
                "writePermission": { "type": "string" },
                "grantUriPermissions": { "type": "boolean" }
              },
              "required": ["name", "authorities", "exported", "permission", "readPermission", "writePermission", "grantUriPermissions"],
              "additionalProperties": false
            }
          }
        },
        "required": ["activities", "services", "receivers", "providers"],
        "additionalProperties": false
      },
      "strict": true
    }
  }
  FORMAT
  # Map of LLM providers and their models to their max token limits
  # This helps determine how many files can be bundled together
  MODEL_TOKEN_LIMITS = {
    "openai" => {
      "gpt-3.5-turbo"     => 16385,
      "gpt-3.5-turbo-16k" => 16385,
      "gpt-4"             => 8192,
      "gpt-4-32k"         => 32768,
      "gpt-4o"            => 128000,
      "gpt-4o-mini"       => 128000,
      "default"           => 8000,
    },
    "xai" => {
      "grok-1"  => 8192,
      "grok-2"  => 131072,
      "grok-3"  => 131072,
      "default" => 8000,
    },
    "anthropic" => {
      "claude-3-opus"   => 200000,
      "claude-3-sonnet" => 200000,
      "claude-3-haiku"  => 200000,
      "claude-2"        => 100000,
      "default"         => 100000,
    },
    "azure" => {
      "default" => 8000,
    },
    "github" => {
      "default" => 8000,
    },
    "ollama" => {
      "llama3"  => 8192,
      "phi3"    => 8192,
      "mistral" => 8192,
      "phi2"    => 2048,
      "default" => 4000,
    },
    "vllm" => {
      "default" => 4000,
    },
    "lmstudio" => {
      "default" => 4000,
    },
    "default" => 4000,
  }

  # Estimate the number of tokens in a string
  # This is a rough estimate using 1 token ≈ 4 characters for English text
  def self.estimate_tokens(text : String) : Int32
    if text.size < 1024
      250
    else
      (text.size / 4.0).ceil.to_i
    end
  end

  # Get the maximum token limit for a given provider and model
  def self.get_max_tokens(provider : String, model : String) : Int32
    provider = provider.downcase

    # Extract just the provider name if URL was provided
    if provider.includes?("://") || provider.includes?(".")
      # For URLs like "https://api.openai.com" or "openai.com"
      if provider.includes?("openai")
        provider = "openai"
      elsif provider.includes?("anthropic")
        provider = "anthropic"
      elsif provider.includes?("x.ai") || provider.includes?("xai")
        provider = "xai"
      elsif provider.includes?("github")
        provider = "github"
      elsif provider.includes?("azure")
        provider = "azure"
      elsif provider.includes?("ollama")
        provider = "ollama"
      elsif provider.includes?("vllm")
        provider = "vllm"
      elsif provider.includes?("lmstudio")
        provider = "lmstudio"
      end
    end

    # Get the provider-specific limits or fall back to default
    provider_limits = MODEL_TOKEN_LIMITS[provider]? || MODEL_TOKEN_LIMITS["default"]

    if provider_limits.is_a?(Hash)
      # Get the model-specific limit or fall back to provider default
      if provider_limits.as(Hash).has_key?(model)
        provider_limits.as(Hash)[model].as(Int32)
      else
        provider_limits.as(Hash)["default"].as(Int32)
      end
    else
      provider_limits.as(Int32)
    end
  end

  # Create a bundle of files that fits within token limits
  # Returns the bundle content and the estimated token count
  def self.bundle_files(files : Array(Tuple(String, String)),
                        max_tokens : Int32,
                        safety_margin : Float64 = 0.8) : Array(Tuple(String, Int32))
    safe_limit = (max_tokens * safety_margin).to_i
    bundles = [] of Tuple(String, Int32)
    current_bundle = ""
    current_tokens = estimate_tokens(BUNDLE_ANALYZE_PROMPT)

    files.each do |file_path, content|
      file_section = "- File: \"#{file_path}\"\n```\n#{content}\n```\n"
      file_tokens = estimate_tokens(file_section)

      if current_tokens + file_tokens > safe_limit && !current_bundle.empty?
        bundles << {current_bundle, current_tokens}
        current_bundle = ""
        current_tokens = estimate_tokens(BUNDLE_ANALYZE_PROMPT)
      end

      current_bundle += file_section
      current_tokens += file_tokens
    end

    if !current_bundle.empty?
      bundles << {current_bundle, current_tokens}
    end

    bundles
  end
end
