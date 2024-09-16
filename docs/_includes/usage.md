USAGE: noir <flags>

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
    --set-pvalue VALUE               Specifies the value of the identified parameter
    --include-path                   Include file path in the plain result
    --no-color                       Disable color output
    --no-log                         Displaying only the results

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

  DIFF:
    --diff-path ./app2               Specify the path to the old version of the source code for comparison

  TECHNOLOGIES:
    -t TECHS, --techs rails,php      Specify the technologies to use
    --exclude-techs rails,php        Specify the technologies to be excluded
    --list-techs                     Show all technologies

  CONFIG:
    --config-file ./config.yaml      Specify the path to a configuration file in YAML format
    --concurrency 100                Set concurrency
    --generate-completion zsh        Generate Zsh/Bash completion script

  DEBUG:
    -d, --debug                      Show debug messages
    -v, --version                    Show version
    --build-info                     Show version and Build info

  OTHERS:
    -h, --help                       Show help

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
