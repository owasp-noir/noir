module LLM
  FILTER_PROMPT = <<-PROMPT
  Analyze the following list of file paths and identify which files are likely to represent endpoints, including API endpoints, web pages, or static resources.

  Guidelines:
  - Focus only on individual files.
  - Do not include directories.
  - Do not include explanations, comments or additional text.

  Input Files:
  PROMPT

  FILTER_FORMAT = <<-FORMAT
  {
    "type": "object",
    "properties": {
      "files": {
        "type": "array",
        "items": {
          "type": "string"
        }
      }
    }
  },
  "required": ["files"]
  }
  FORMAT

  ANALYZE_PROMPT = <<-PROMPT
  Analyze the provided source code to extract details about the endpoints and their parameters.

  Guidelines:
  - The "method" field should strictly use one of these values: "GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD".
  - The "param_type" must strictly use one of these values: "query", "json", "form", "header", "cookie" and "path".
  - Do not include explanations, comments or additional text.

  Input Code:
  PROMPT

  ANALYZE_FORMAT = <<-FORMAT
  {
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
                "required": ["name", "param_type", "value"]
              }
            }
          },
          "required": ["url", "method", "params"]
        }
      }
    },
    "required": ["endpoints"]
  }
  FORMAT
end
