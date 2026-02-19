# LLM prompts and formats for AI-powered endpoint analysis

module LLM
  SHARED_RULES       = "Output only JSON. No explanations. method in [GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD]. param_type in [query, json, form, header, cookie, path]."
  AGENT_SHARED_RULES = "Output only JSON. No markdown fences. Use only the defined action names. Do not guess endpoints without reading code."

  SYSTEM_FILTER  = "#{SHARED_RULES} Given a list of file paths, return JSON with property files: string[] of likely endpoints (no directories)."
  SYSTEM_ANALYZE = "#{SHARED_RULES} Given source code, return JSON with endpoints: [{url, method, params:[{name, param_type, value}]}]."
  SYSTEM_BUNDLE  = "#{SHARED_RULES} Given a bundle of files, include endpoints from ALL files; return the same JSON schema."
  SYSTEM_AGENT   = "#{AGENT_SHARED_RULES} You are OWASP Noir Advanced Endpoint Discovery Agent. Use iterative tool actions until enough evidence is collected, then finalize."

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

  FILTER_FORMAT = <<-JSON
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
    JSON

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

  ANALYZE_FORMAT = <<-JSON
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
    JSON

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

  AGENT_PROMPT = <<-PROMPT
    You are OWASP Noir's endpoint discovery agent.
    Your goal is to discover all API endpoints from source code with high confidence.

    Allowed actions:
    - list_directory(path: string = ".", max_depth: integer = 3)
    - read_file(path: string)
    - grep(pattern: string, path: string = ".", file_pattern: string = "*")
    - semantic_search(query: string)
    - finalize(endpoints: array, summary: string, confidence: integer 0..100)

    Rules:
    - First inspect project structure with list_directory or grep.
    - Never assume endpoint existence from filenames only.
    - Read source files before finalizing.
    - Use finalize only when confident enough.
    - Keep endpoint method to [GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD].
    - Use param_type in [query, json, form, header, cookie, path].
    PROMPT

  AGENT_STEP_FORMAT = <<-JSON
    {
      "type": "json_schema",
      "json_schema": {
        "name": "agent_next_action",
        "schema": {
          "type": "object",
          "properties": {
            "action": {
              "type": "string",
              "enum": ["list_directory", "read_file", "grep", "semantic_search", "finalize"]
            },
            "args": {
              "type": "object",
              "additionalProperties": true
            }
          },
          "required": ["action", "args"],
          "additionalProperties": false
        },
        "strict": true
      }
    }
    JSON

  AGENT_TOOLS = <<-JSON
    [
      {
        "type": "function",
        "function": {
          "name": "list_directory",
          "description": "Return project directory structure up to max_depth.",
          "parameters": {
            "type": "object",
            "properties": {
              "path": {
                "type": "string",
                "default": "."
              },
              "max_depth": {
                "type": "integer",
                "minimum": 1,
                "maximum": 6,
                "default": 3
              }
            },
            "additionalProperties": false
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "read_file",
          "description": "Read file content for endpoint extraction.",
          "parameters": {
            "type": "object",
            "properties": {
              "path": {
                "type": "string"
              }
            },
            "required": ["path"],
            "additionalProperties": false
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "grep",
          "description": "Regex search in codebase.",
          "parameters": {
            "type": "object",
            "properties": {
              "pattern": {
                "type": "string"
              },
              "path": {
                "type": "string",
                "default": "."
              },
              "file_pattern": {
                "type": "string",
                "default": "*"
              }
            },
            "required": ["pattern"],
            "additionalProperties": false
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "semantic_search",
          "description": "Semantic-like search for code using natural language query.",
          "parameters": {
            "type": "object",
            "properties": {
              "query": {
                "type": "string"
              }
            },
            "required": ["query"],
            "additionalProperties": false
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "finalize",
          "description": "Finalize extraction and return endpoint list.",
          "parameters": {
            "type": "object",
            "properties": {
              "endpoints": {
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "url": { "type": "string" },
                    "path": { "type": "string" },
                    "method": { "type": "string" },
                    "file": { "type": "string" },
                    "line": { "type": "integer" },
                    "params": {
                      "type": "array",
                      "items": {
                        "type": "object",
                        "properties": {
                          "name": { "type": "string" },
                          "param_type": { "type": "string" },
                          "value": { "type": "string" }
                        },
                        "required": ["name"],
                        "additionalProperties": true
                      }
                    }
                  },
                  "required": ["method"],
                  "additionalProperties": true
                }
              },
              "summary": { "type": "string" },
              "confidence": { "type": "integer" }
            },
            "required": ["endpoints"],
            "additionalProperties": true
          }
        }
      }
    ]
    JSON

  # Map of LLM providers and their models to their max token limits
  # This helps determine how many files can be bundled together
  MODEL_TOKEN_LIMITS = {
    "openai" => {
      "gpt-3.5-turbo"        => 16385,
      "gpt-3.5-turbo-16k"    => 16385,
      "gpt-4"                => 8192,
      "gpt-4-32k"            => 32768,
      "gpt-4-turbo"          => 128000,
      "gpt-4-turbo-preview"  => 128000,
      "gpt-4-vision-preview" => 128000,
      "gpt-4-1106-preview"   => 128000,
      "gpt-4-0125-preview"   => 128000,
      "gpt-4o"               => 128000,
      "gpt-4o-mini"          => 128000,
      "o1-preview"           => 128000,
      "o1-mini"              => 128000,
      "o3-mini"              => 200000,
      "gpt-5"                => 1000000,
      "gpt-5.1"              => 1000000,
      "gpt-5-mini"           => 1000000,
      "gpt-5-codex-max"      => 1000000,
      "gpt-5.1-codex-max"    => 1000000,
      "default"              => 8000,
    },
    "xai" => {
      "grok-1"                    => 8192,
      "grok-2"                    => 131072,
      "grok-2-mini"               => 131072,
      "grok-beta"                 => 131072,
      "grok-3"                    => 1000000,
      "grok-4"                    => 2000000,
      "grok-4-fast-reasoning"     => 2000000,
      "grok-4-fast-non-reasoning" => 2000000,
      "grok-code-fast"            => 2000000,
      "grok-code-fast-1"          => 2000000,
      "default"                   => 8000,
    },
    "anthropic" => {
      "claude-3-opus"      => 200000,
      "claude-3-sonnet"    => 200000,
      "claude-3-haiku"     => 200000,
      "claude-3-5-sonnet"  => 200000,
      "claude-3-5-haiku"   => 200000,
      "claude-2"           => 100000,
      "claude-2.0"         => 100000,
      "claude-2.1"         => 200000,
      "claude-instant-1.2" => 100000,
      "claude-sonnet-4"    => 1000000,
      "claude-sonnet-4-5"  => 1000000,
      "claude-haiku-4-5"   => 200000,
      "claude-opus-4"      => 200000,
      "claude-opus-4-1"    => 200000,
      "claude-opus-4.1"    => 200000,
      "claude-opus-4-5"    => 200000,
      "default"            => 100000,
    },
    "azure" => {
      "gpt-3.5-turbo"        => 16385,
      "gpt-3.5-turbo-16k"    => 16385,
      "gpt-4"                => 8192,
      "gpt-4-32k"            => 32768,
      "gpt-4-turbo"          => 128000,
      "gpt-4-turbo-preview"  => 128000,
      "gpt-4-vision-preview" => 128000,
      "gpt-4o"               => 128000,
      "gpt-4o-mini"          => 128000,
      "o1-preview"           => 128000,
      "o1-mini"              => 128000,
      "gpt-4.1"              => 1000000,
      "gpt-5-codex-max"      => 1000000,
      "gpt-5.1-codex-max"    => 1000000,
      "default"              => 8000,
    },
    "github" => {
      "gpt-4o"                       => 64000,
      "gpt-4o-mini"                  => 64000,
      "Phi-3.5-mini-instruct"        => 128000,
      "Phi-3.5-MoE-instruct"         => 128000,
      "Meta-Llama-3.1-405B-Instruct" => 128000,
      "Meta-Llama-3.1-70B-Instruct"  => 128000,
      "Meta-Llama-3.1-8B-Instruct"   => 128000,
      "Mistral-large"                => 128000,
      "Mistral-large-2407"           => 128000,
      "Mistral-Nemo"                 => 128000,
      "Mistral-small"                => 32768,
      "AI21-Jamba-1.5-Large"         => 256000,
      "AI21-Jamba-1.5-Mini"          => 256000,
      "Cohere-command-r"             => 128000,
      "Cohere-command-r-plus"        => 128000,
      "default"                      => 8000,
    },
    "ollama" => {
      "llama3"         => 128000,
      "llama3.1"       => 128000,
      "llama3.2"       => 128000,
      "llama3.3"       => 128000,
      "phi2"           => 2048,
      "phi3"           => 128000,
      "phi3.5"         => 128000,
      "gemma"          => 8192,
      "gemma2"         => 8192,
      "mistral"        => 32768,
      "mixtral"        => 32768,
      "codellama"      => 100000,
      "deepseek-coder" => 100000,
      "qwen2"          => 128000,
      "qwen2.5"        => 128000,
      "gpt-oss"        => 128000,
      "gpt-oss-120b"   => 128000,
      "gpt-oss-20b"    => 128000,
      "default"        => 4000,
    },
    "google" => {
      "gemini-1.5-pro"       => 2097152,
      "gemini-1.5-flash"     => 1048576,
      "gemini-1.0-pro"       => 32760,
      "gemini-pro"           => 32760,
      "gemini-pro-vision"    => 16384,
      "gemini-2.0-flash-exp" => 1048576,
      "gemini-2.5-pro"       => 2000000,
      "gemini-3-pro-preview" => 2000000,
      "default"              => 32760,
    },
    "cohere" => {
      "command-r"             => 256000,
      "command-r-plus"        => 256000,
      "command"               => 4096,
      "command-light"         => 4096,
      "command-nightly"       => 8192,
      "command-light-nightly" => 8192,
      "default"               => 4096,
    },
    "vllm" => {
      "default" => 4000,
    },
    "lmstudio" => {
      "gpt-oss"      => 128000,
      "gpt-oss-120b" => 128000,
      "gpt-oss-20b"  => 128000,
      "default"      => 4000,
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
      elsif provider.includes?("google") || provider.includes?("gemini")
        provider = "google"
      elsif provider.includes?("cohere")
        provider = "cohere"
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
    current_tokens = estimate_tokens(SYSTEM_BUNDLE)

    files.each do |file_path, content|
      file_section = "- File: \"#{file_path}\"\n```\n#{content}\n```\n"
      file_tokens = estimate_tokens(file_section)

      if current_tokens + file_tokens > safe_limit && !current_bundle.empty?
        bundles << {current_bundle, current_tokens}
        current_bundle = ""
        current_tokens = estimate_tokens(SYSTEM_BUNDLE)
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
