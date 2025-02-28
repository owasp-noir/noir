Attack surface detector that identifies endpoints by static analysis.
USAGE:
  noir -b BASE_PATH <flags>

FLAGS:
  BASE:
    -b PATH, --base-path ./app       (Required) Set base path
    -u URL, --url http://..          Set base url for endpoints

  OUTPUT:
    -f FORMAT, --format json         Set output format
                                       * plain yaml json jsonl markdown-table
                                       * curl httpie oas2 oas3
                                       * only-url only-param only-header only-cookie only-tag
    -o PATH, --output out.txt        Write result to file
    --set-pvalue VALUE               Specifies the value of the identified parameter for all types
    --set-pvalue-header VALUE        Specifies the value of the identified parameter for headers
    --set-pvalue-cookie VALUE        Specifies the value of the identified parameter for cookies
    --set-pvalue-query VALUE         Specifies the value of the identified parameter for query parameters
    --set-pvalue-form VALUE          Specifies the value of the identified parameter for form data
    --set-pvalue-json VALUE          Specifies the value of the identified parameter for JSON data
    --set-pvalue-path VALUE          Specifies the value of the identified parameter for path parameters
    --status-codes                   Display HTTP status codes for discovered endpoints
    --exclude-codes 404,500          Exclude specific HTTP response codes (comma-separated)
    --include-path                   Include file path in the plain result
    --no-color                       Disable color output
    --no-log                         Displaying only the results

  PASSIVE SCAN:
    -P, --passive-scan               Perform a passive scan for security issues using rules from the specified path
    --passive-scan-path PATH         Specify the path for the rules used in the passive security scan

  TAGGER:
    -T, --use-all-taggers            Activates all taggers for full analysis coverage
    --use-taggers VALUES             Activates specific taggers (e.g., --use-taggers hunt,oauth)
    --list-taggers                   Lists all available taggers

  DELIVER:
    --send-req                       Send results to a web request
    --send-proxy http://proxy..      Send results to a web request via an HTTP proxy
    --send-es http://es..            Send results to Elasticsearch
    --with-headers X-Header:Value    Add custom headers to be included in the delivery
    --use-matchers string            Send URLs that match specific conditions to the Deliver
    --use-filters string             Exclude URLs that match specified conditions and send the rest to Deliver

  AI Integration:
    --ai-provider PREFIX|URL         Specify the AI (LLM) provider or directly set a custom API URL. Required for AI features.
                                       [Prefixes and Default URLs]
                                       * openai: https://api.openai.com
                                       * x.ai: https://api.x.ai
                                       * azure: https://models.inference.ai.azure.com
                                       * vllm: http://localhost:8000
                                       * ollama: http://localhost:11434
                                       * lmstudio: http://localhost:1234
                                       [Custom URL] You can also provide a full URL directly (e.g., http://my-custom-api:9000).
                                       [Examples] --ai-provider=openai, --ai-provider=http://localhost:9100/v1/chat/completions
    --ai-model MODEL                 Set the model name to use for AI analysis. Required for AI features.
                                       [Example] --ai-model=gpt-4
    --ai-key KEY                     Provide the API key for authenticating with the AI provider's API. Alternatively, use the NOIR_AI_KEY environment variable.
                                       [Example] --ai-key=your-api-key  or  export NOIR_AI_KEY=your-api-key
    --ollama http://localhost:11434  (Deprecated) Set the Ollama server URL. Use --ai-provider instead.
    --ollama-model MODEL             (Deprecated) Specify the model for the Ollama server. Use --ai-model instead.

  DIFF:
    --diff-path ./app2               Specify the path to the old version of the source code for comparison

  TECHNOLOGIES:
    -t TECHS, --techs rails,php      Specify the technologies to use
    --exclude-techs rails,php        Specify the technologies to be excluded
    --list-techs                     Show all technologies

  CONFIG:
    --config-file ./config.yaml      Specify the path to a configuration file in YAML format
    --concurrency 50                 Set concurrency
    --generate-completion zsh        Generate Zsh/Bash/Fish completion script

  DEBUG:
    -d, --debug                      Show debug messages
    -v, --version                    Show version
    --build-info                     Show version and Build info
    --verbose                        Show verbose messages (+ automatically enable --include-path, --use-all-taggers)

  OTHERS:
    -h, --help                       Show help
    --help-all                       Show all help

ENVIRONMENT VARIABLES:
  NOIR_HOME: Path to a directory containing the configuration file.
  NOIR_AI_KEY: API key for authenticating with an AI provider (e.g., OpenAI, xAI)

EXAMPLES:
  Basic run of noir:
      $ noir -b .
  Running noir targeting a specific URL and forwarding results through a proxy:
      $ noir -b . -u http://example.com
      $ noir -b . -u http://example.com --send-proxy http://localhost:8090
  Running noir for detailed analysis:
      $ noir -b . -T --include-path
  Running noir with output limited to JSON or YAML format, without logs:
      $ noir -b . -f json --no-log
      $ noir -b . -f yaml --no-log
  Running noir with a specific technology:
      $ noir -b . -t rails
  Running noir with a specific technology and excluding another:
      $ noir -b . -t rails --exclude-techs php
  Running noir with AI integration:
      $ noir -b . --ollama http://localhost:11434 --ollama-model llama3
