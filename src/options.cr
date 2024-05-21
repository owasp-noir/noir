def default_options
  noir_options = {
    :base              => "",
    :color             => "yes",
    :config_file       => "",
    :concurrency       => "100",
    :debug             => "no",
    :exclude_techs     => "",
    :format            => "plain",
    :include_path      => "no",
    :nolog             => "no",
    :output            => "",
    :send_es           => "",
    :send_proxy        => "",
    :send_req          => "no",
    :send_with_headers => "",
    :set_pvalue        => "",
    :techs             => "",
    :url               => "",
    :use_filters       => "",
    :use_matchers      => "",
    :all_taggers       => "no",
    :use_taggers       => "",
    :diff              => "",
  }

  noir_options
end

def run_options_parser
  noir_options = default_options()

  OptionParser.parse do |parser|
    parser.banner = "USAGE: noir <flags>\n"
    parser.separator "FLAGS:"
    parser.separator "  BASE:".colorize(:blue)
    parser.on "-b PATH", "--base-path ./app", "(Required) Set base path" { |var| noir_options[:base] = var }
    parser.on "-u URL", "--url http://..", "Set base url for endpoints" { |var| noir_options[:url] = var }

    parser.separator "\n  OUTPUT:".colorize(:blue)
    parser.on "-f FORMAT", "--format json", "Set output format\n  * plain yaml json jsonl markdown-table\n  * curl httpie oas2 oas3\n  * only-url only-param only-header only-cookie" { |var| noir_options[:format] = var }
    parser.on "-o PATH", "--output out.txt", "Write result to file" { |var| noir_options[:output] = var }
    parser.on "--set-pvalue VALUE", "Specifies the value of the identified parameter" { |var| noir_options[:set_pvalue] = var }
    parser.on "--include-path", "Include file path in the plain result" do
      noir_options[:include_path] = "yes"
    end
    parser.on "--no-color", "Disable color output" do
      noir_options[:color] = "no"
    end
    parser.on "--no-log", "Displaying only the results" do
      noir_options[:nolog] = "yes"
    end

    parser.separator "\n  TAGGER:".colorize(:blue)
    parser.on "-T", "--use-all-taggers", "Activates all taggers for full analysis coverage" { |_| noir_options[:all_taggers] = "yes" }
    parser.on "--use-taggers VALUES", "Activates specific taggers (e.g., --use-taggers hunt,oauth)" { |var| noir_options[:use_taggers] = var }
    parser.on "--list-taggers", "Lists all available taggers" do
      puts "Available taggers:"
      techs = NoirTaggers.get_taggers
      techs.each do |tagger, value|
        puts "  #{tagger.to_s.colorize(:green)}"
        value.each do |k, v|
          puts "    #{k.to_s.colorize(:blue)}: #{v}"
        end
      end
      exit
    end

    parser.separator "\n  DELIVER:".colorize(:blue)
    parser.on "--send-req", "Send results to a web request" { |_| noir_options[:send_req] = "yes" }
    parser.on "--send-proxy http://proxy..", "Send results to a web request via an HTTP proxy" { |var| noir_options[:send_proxy] = var }
    parser.on "--send-es http://es..", "Send results to Elasticsearch" { |var| noir_options[:send_es] = var }
    parser.on "--with-headers X-Header:Value", "Add custom headers to be included in the delivery" do |var|
      noir_options[:send_with_headers] += "#{var}::NOIR::HEADERS::SPLIT::"
    end
    parser.on "--use-matchers string", "Send URLs that match specific conditions to the Deliver" do |var|
      noir_options[:use_matchers] += "#{var}::NOIR::MATCHER::SPLIT::"
    end
    parser.on "--use-filters string", "Exclude URLs that match specified conditions and send the rest to Deliver" do |var|
      noir_options[:use_filters] += "#{var}::NOIR::FILTER::SPLIT::"
    end

    parser.separator "\n  DIFF:".colorize(:blue)
    parser.on "--diff-path ./app2", "Specify the path to the old version of the source code for comparison" { |var| noir_options[:diff] = var }

    parser.separator "\n  TECHNOLOGIES:".colorize(:blue)
    parser.on "-t TECHS", "--techs rails,php", "Specify the technologies to use" { |var| noir_options[:techs] = var }
    parser.on "--exclude-techs rails,php", "Specify the technologies to be excluded" { |var| noir_options[:exclude_techs] = var }
    parser.on "--list-techs", "Show all technologies" do
      puts "Available technologies:"
      techs = NoirTechs.get_techs
      techs.each do |tech, value|
        puts "  #{tech.to_s.colorize(:green)}"
        value.each do |k, v|
          puts "    #{k.to_s.colorize(:blue)}: #{v}"
        end
      end
      exit
    end

    parser.separator "\n  CONFIG:".colorize(:blue)
    parser.on "--config-file ./config.yaml", "Specify the path to a configuration file in YAML format" { |var| noir_options[:config_file] = var }
    parser.on "--concurrency 100", "Set concurrency" { |var| noir_options[:concurrency] = var }

    parser.separator "\n  OTHERS:".colorize(:blue)
    parser.on "-d", "--debug", "Show debug messages" do
      noir_options[:debug] = "yes"
    end
    parser.on "-v", "--version", "Show version" do
      puts "Noir Version: #{Noir::VERSION}"
      puts "Build Info: #{Crystal::DESCRIPTION}"
      exit
    end
    parser.on "-h", "--help", "Show help" do
      puts parser
      puts ""
      puts "EXAMPLES:"
      puts "  Basic run of noir:".colorize(:green)
      puts "      $ noir -b ."
      puts "  Running noir targeting a specific URL and forwarding results through a proxy:".colorize(:green)
      puts "      $ noir -b . -u http://example.com"
      puts "      $ noir -b . -u http://example.com --send-proxy http://localhost:8090"
      puts "  Running noir for detailed analysis:".colorize(:green)
      puts "      $ noir -b . -T --include-path"
      puts "  Running noir with output limited to JSON or YAML format, without logs:".colorize(:green)
      puts "      $ noir -b . -f json --no-log"
      puts "      $ noir -b . -f yaml --no-log"
      exit
    end
    parser.invalid_option do |flag|
      STDERR.puts "ERROR: #{flag} is not a valid option."
      STDERR.puts parser
      exit(1)
    end
    parser.missing_option do |flag|
      STDERR.puts "ERROR: #{flag} is missing an argument."
      exit(1)
    end
  end

  noir_options
end
