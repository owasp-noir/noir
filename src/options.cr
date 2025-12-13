require "./completions.cr"
require "./config_initializer.cr"
require "./banner.cr"
require "yaml"

private def append_to_yaml_array(hash : Hash(String, YAML::Any), key : String, value : String)
  arr = (hash[key]? || YAML::Any.new([] of YAML::Any)).as_a.dup
  arr << YAML::Any.new(value)
  hash[key] = YAML::Any.new(arr)
end

private def process_override_flag(
  flag : String, option_key : String,
  noir_options : Hash(String, YAML::Any),
  args : Array(String), i : Int32
) : Int32
  if i + 1 < args.size && !args[i + 1].starts_with?("-")
    noir_options[option_key] = YAML::Any.new(args[i + 1])
    i + 2
  else
    STDERR.puts "ERROR: #{flag} requires an argument.".colorize(:yellow)
    exit(1)
  end
end

def extract_hidden_prompt_flags(noir_options : Hash(String, YAML::Any)) : Array(String)
  args = ARGV.dup
  filtered = [] of String
  i = 0
  override_flags = {
    "--override-analyze-prompt"        => "override_analyze_prompt",
    "--override-llm-optimize-prompt"   => "override_llm_optimize_prompt",
    "--override-bundle-analyze-prompt" => "override_bundle_analyze_prompt",
    "--override-filter-prompt"         => "override_filter_prompt",
  }

  while i < args.size
    arg = args[i]
    if override_flags.has_key?(arg)
      i = process_override_flag(arg, override_flags[arg], noir_options, args, i)
    else
      filtered << arg
      i += 1
    end
  end
  filtered
end

private def base_help : String
  <<-HELP
  #{"Hunt every Endpoint, expose Shadow APIs, map the Attack Surface.".colorize(:cyan)}

  #{"USAGE:".colorize(:green)}
    noir -b BASE_PATH [flags]

  #{"EXAMPLES:".colorize(:green)}
    #{"Basic scan".colorize(:yellow)}
      noir -b ./myapp

    #{"JSON output to file".colorize(:yellow)}
      noir -b ./myapp -f json -o endpoints.json

    #{"Enable passive security scan".colorize(:yellow)}
      noir -b ./myapp -P

    #{"AI integration".colorize(:yellow)}
      $ noir -b . --ai-provider openai --ai-model gpt-5.1 --ai-key YOUR_API_KEY

    #{"Forward results via proxy (Burp/ZAP)".colorize(:yellow)}
      noir -b ./myapp --send-proxy http://127.0.0.1:8080

  HELP
end

private def full_examples_and_env : String
  <<-EXTRA
  \n#{"EXAMPLES:".colorize(:green)}
    #{"Basic run".colorize(:yellow)}
      $ noir -b .

    #{"With base URL and proxy".colorize(:yellow)}
      $ noir -b . -u http://example.com --send-proxy http://localhost:8090

    #{"Detailed analysis".colorize(:yellow)}
      $ noir -b . -T --include-path

    #{"JSON or YAML output without logs".colorize(:yellow)}
      $ noir -b . -f json --no-log
      $ noir -b . -f yaml --no-log

    #{"Specific technology".colorize(:yellow)}
      $ noir -b . -t rails
      $ noir -b . -t rails --exclude-techs php

  #{"ENVIRONMENT VARIABLES:".colorize(:green)}
    NOIR_HOME          Path to directory containing config file
    NOIR_AI_KEY        API key for AI providers (OpenAI, xAI, etc.)
    NOIR_MAX_FILE_SIZE Maximum file size for analysis (e.g. 5MB or 1048576)
  EXTRA
end

def run_options_parser
  config_init = ConfigInitializer.new
  noir_options = config_init.read_config

  extracted_args = extract_hidden_prompt_flags(noir_options)

  OptionParser.parse(extracted_args) do |parser|
    parser.banner = base_help

    parser.separator "FLAGS:".colorize(:green)

    parser.separator " BASE:".colorize(:blue)
    parser.on "-b PATH", "--base-path ./app", "(Required) Set base path" do |v|
      append_to_yaml_array(noir_options, "base", v)
    end
    parser.on "-u URL", "--url http://..", "Set base URL for endpoints" do |v|
      noir_options["url"] = YAML::Any.new(v)
    end

    parser.separator "\n OUTPUT:".colorize(:blue)
    parser.on "-f FMT", "--format json", <<-DESC do |v|
      Output format:
        plain                Plain text (default)
        yaml                 YAML
        json                 JSON
        jsonl                JSON Lines
        markdown-table       Markdown table
        sarif                SARIF format
        html                 HTML report
        curl                 cURL commands
        httpie               HTTPie commands
        oas2                 OpenAPI 2.0 (Swagger)
        oas3                 OpenAPI 3.0
        postman              Postman collection
        only-url             Only endpoint URLs
        only-param           Only parameters
        only-header          Only headers
        only-cookie          Only cookies
        only-tag             Only tags
        mermaid              Mermaid diagram
      DESC
      noir_options["format"] = YAML::Any.new(v)
    end
    parser.on "-o PATH", "--output out.txt", "Write result to file" do |v|
      noir_options["output"] = YAML::Any.new(v)
    end

    parser.on "--set-pvalue VALUE", "Set parameter value for all types" do |v|
      append_to_yaml_array(noir_options, "set_pvalue", v)
    end
    parser.on "--set-pvalue-header VALUE", "Set parameter value for headers" do |v|
      append_to_yaml_array(noir_options, "set_pvalue_header", v)
    end
    parser.on "--set-pvalue-cookie VALUE", "Set parameter value for cookies" do |v|
      append_to_yaml_array(noir_options, "set_pvalue_cookie", v)
    end
    parser.on "--set-pvalue-query VALUE", "Set parameter value for query parameters" do |v|
      append_to_yaml_array(noir_options, "set_pvalue_query", v)
    end
    parser.on "--set-pvalue-form VALUE", "Set parameter value for form data" do |v|
      append_to_yaml_array(noir_options, "set_pvalue_form", v)
    end
    parser.on "--set-pvalue-json VALUE", "Set parameter value for JSON body" do |v|
      append_to_yaml_array(noir_options, "set_pvalue_json", v)
    end
    parser.on "--set-pvalue-path VALUE", "Set parameter value for path parameters" do |v|
      append_to_yaml_array(noir_options, "set_pvalue_path", v)
    end

    parser.on "--status-codes", "Display HTTP status codes" do
      noir_options["status_codes"] = YAML::Any.new(true)
    end
    parser.on "--exclude-codes 404,500", "Exclude HTTP codes (comma-separated)" do |v|
      noir_options["exclude_codes"] = YAML::Any.new(v)
    end
    parser.on "--include-path", "Include file path in plain output" do
      noir_options["include_path"] = YAML::Any.new(true)
    end
    parser.on "--no-color", "Disable color output" do
      noir_options["color"] = YAML::Any.new(false)
    end
    parser.on "--no-log", "Show only results" do
      noir_options["nolog"] = YAML::Any.new(true)
    end

    parser.separator "\n PASSIVE SCAN:".colorize(:blue)
    parser.on "-P", "--passive-scan", "Enable passive security scan" do
      noir_options["passive_scan"] = YAML::Any.new(true)
    end
    parser.on "--passive-scan-path PATH", "Path to passive scan rules" do |v|
      append_to_yaml_array(noir_options, "passive_scan_path", v)
    end
    parser.on "--passive-scan-severity LVL", "Min severity (critical|high|medium|low, default: high)" do |v|
      lvl = v.downcase
      if %w[critical high medium low].includes?(lvl)
        noir_options["passive_scan_severity"] = YAML::Any.new(lvl)
      else
        STDERR.puts "ERROR: Invalid severity '#{v}'. Valid: critical, high, medium, low".colorize(:yellow)
        exit(1)
      end
    end
    parser.on "--passive-scan-auto-update", "Auto-update rules at startup" do
      noir_options["passive_scan_auto_update"] = YAML::Any.new(true)
    end
    parser.on "--passive-scan-no-update-check", "Skip rule update check" do
      noir_options["passive_scan_no_update_check"] = YAML::Any.new(true)
    end

    parser.separator "\n TAGGER:".colorize(:blue)
    parser.on "-T", "--use-all-taggers", "Activate all taggers" do
      noir_options["all_taggers"] = YAML::Any.new(true)
    end
    parser.on "--use-taggers LIST", "Activate specific taggers (comma-separated)" do |v|
      noir_options["use_taggers"] = YAML::Any.new(v)
    end
    parser.on "--list-taggers", "List available taggers" do
      puts "Available taggers:"
      NoirTaggers.taggers.each do |tagger, info|
        puts " #{tagger.to_s.colorize(:green)}"
        info.each { |k, v| puts "   #{k.to_s.colorize(:blue)}: #{v}" }
      end
      exit
    end

    parser.separator "\n DELIVER:".colorize(:blue)
    parser.on "--send-req", "Send results via HTTP request" do
      noir_options["send_req"] = YAML::Any.new(true)
    end
    parser.on "--send-proxy URL", "Proxy for delivery" do |v|
      noir_options["send_proxy"] = YAML::Any.new(v)
    end
    parser.on "--send-es URL", "Send to Elasticsearch" do |v|
      noir_options["send_es"] = YAML::Any.new(v)
    end
    parser.on "--with-headers VAL", "Add custom headers (repeatable)" do |v|
      append_to_yaml_array(noir_options, "send_with_headers", v)
    end
    parser.on "--use-matchers VAL", "Matchers for delivery (repeatable)" do |v|
      append_to_yaml_array(noir_options, "use_matchers", v)
    end
    parser.on "--use-filters VAL", "Filters for delivery (repeatable)" do |v|
      append_to_yaml_array(noir_options, "use_filters", v)
    end

    parser.separator "\n AI Integration:".colorize(:blue)
    parser.on "--ai-provider PREFIX|URL", <<-DESC do |v|
      Specify AI provider prefix or full custom URL (required for AI features).

      Supported prefixes:
        openai   → https://api.openai.com/v1
        xai      → https://api.x.ai/v1
        github   → https://models.github.ai/inference
        azure    → https://models.inference.ai.azure.com
        ollama   → http://localhost:11434/v1
        lmstudio → http://localhost:1234/v1
        vllm     → http://localhost:8000/v1

      Or use a custom URL directly:
        --ai-provider http://localhost:8000/v1
      DESC
      noir_options["ai_provider"] = YAML::Any.new(v)
    end
    parser.on "--ai-model NAME", "Model name" do |v|
      noir_options["ai_model"] = YAML::Any.new(v)
    end
    parser.on "--ai-key KEY", "API key (or set NOIR_AI_KEY env)" do |v|
      noir_options["ai_key"] = YAML::Any.new(v)
    end
    parser.on "--ai-max-token N", "Max tokens per request" do |v|
      noir_options["ai_max_token"] = YAML::Any.new(v.to_i)
    end
    parser.on "--ollama URL", "(Deprecated) Use --ai-provider instead" do |v|
      noir_options["ollama"] = YAML::Any.new(v)
    end
    parser.on "--ollama-model NAME", "(Deprecated) Use --ai-model instead" do |v|
      noir_options["ollama_model"] = YAML::Any.new(v)
    end

    parser.separator "\n DIFF:".colorize(:blue)
    parser.on "--diff-path PATH", "Old code version for diff" do |v|
      noir_options["diff"] = YAML::Any.new(v)
    end

    parser.separator "\n TECHNOLOGIES:".colorize(:blue)
    parser.on "-t LIST", "--techs rails,php", "Enable specific technologies" do |v|
      noir_options["techs"] = YAML::Any.new(v)
    end
    parser.on "--exclude-techs LIST", "Exclude technologies" do |v|
      noir_options["exclude_techs"] = YAML::Any.new(v)
    end
    parser.on "--list-techs", "List available technologies" do
      puts "Available technologies:"
      NoirTechs.techs.each do |tech, info|
        puts " #{tech.to_s.colorize(:green)}"
        info.each do |k, v|
          if v.is_a?(Hash)
            puts "   #{k.to_s.colorize(:blue)}:"
            v.each { |sk, sv| puts "     #{sk.to_s.colorize(:cyan)}: #{sv}" }
          else
            puts "   #{k.to_s.colorize(:blue)}: #{v}"
          end
        end
      end
      exit
    end

    parser.separator "\n CONFIG:".colorize(:blue)
    parser.on "--config-file PATH", "YAML config file" do |v|
      noir_options["config_file"] = YAML::Any.new(v)
    end
    parser.on "--concurrency N", "Concurrency level" do |v|
      noir_options["concurrency"] = YAML::Any.new(v.to_i)
    end
    parser.on "--generate-completion SHELL", "Generate completion script (zsh|bash|fish)" do |shell|
      case shell
      when "zsh"  then puts generate_zsh_completion_script
      when "bash" then puts generate_bash_completion_script
      when "fish" then puts generate_fish_completion_script
      else
        STDERR.puts "ERROR: Unsupported shell '#{shell}'".colorize(:yellow)
      end
      exit
    end

    parser.separator "\n CACHE:".colorize(:blue)
    parser.on "--cache-disable", "Disable LLM cache" do
      noir_options["cache_disable"] = YAML::Any.new(true)
    end
    parser.on "--cache-clear", "Clear LLM cache before run" do
      noir_options["cache_clear"] = YAML::Any.new(true)
    end

    parser.separator "\n DEBUG:".colorize(:blue)
    parser.on "-d", "--debug", "Enable debug messages" do
      noir_options["debug"] = YAML::Any.new(true)
    end
    parser.on "-v", "--version", "Show version" do
      puts Noir::VERSION
      exit
    end
    parser.on "--build-info", "Show build information" do
      puts "Noir: #{Noir::VERSION}"
      puts "Crystal: #{Crystal::VERSION}"
      puts "LLVM: #{Crystal::LLVM_VERSION}"
      puts "Target: #{Crystal::TARGET_TRIPLE}"
      exit
    end
    parser.on "--verbose", "Verbose mode (+ --include-path + --use-all-taggers)" do
      noir_options["verbose"] = YAML::Any.new(true)
      noir_options["include_path"] = YAML::Any.new(true)
      noir_options["all_taggers"] = YAML::Any.new(true)
    end

    parser.on "-h", "--help", "Show this help" do
      banner()
      puts parser
      exit
    end

    parser.on "--help-all", "Show all help (examples + env vars)" do
      banner()
      puts parser
      puts full_examples_and_env
      exit
    end

    parser.invalid_option do |flag|
      STDERR.puts "ERROR: #{flag} is not a valid option.".colorize(:yellow)
      STDERR.puts parser
      exit(1)
    end

    parser.missing_option do |flag|
      STDERR.puts "ERROR: #{flag} requires an argument.".colorize(:yellow)
      exit(1)
    end
  end

  noir_options
end
