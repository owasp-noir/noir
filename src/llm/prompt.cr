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
end
