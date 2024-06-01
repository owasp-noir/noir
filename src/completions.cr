def generate_zsh_completion_script
  <<-SCRIPT
      #compdef noir

      _arguments \\
        '-b[Set base path]:path:_files' \\
        '-u[Set base URL for endpoints]:URL:_urls' \\
        '-f[Set output format]:format:(plain yaml json jsonl markdown-table curl httpie oas2 oas3 only-url only-param only-header only-cookie)' \\
        '-o[Write result to file]:path:_files' \\
        '--set-pvalue[Specifies the value of the identified parameter]:value:' \\
        '--include-path[Include file path in the plain result]' \\
        '--no-color[Disable color output]' \\
        '--no-log[Displaying only the results]' \\
        '-T[Activates all taggers for full analysis coverage]' \\
        '--use-taggers[Activates specific taggers]:values:' \\
        '--list-taggers[Lists all available taggers]' \\
        '--send-req[Send results to a web request]' \\
        '--send-proxy[Send results to a web request via an HTTP proxy]:proxy:' \\
        '--send-es[Send results to Elasticsearch]:es:' \\
        '--with-headers[Add custom headers to be included in the delivery]:headers:' \\
        '--use-matchers[Send URLs that match specific conditions to the Deliver]:string:' \\
        '--use-filters[Exclude URLs that match specified conditions and send the rest to Deliver]:string:' \\
        '--diff-path[Specify the path to the old version of the source code for comparison]:path:_files' \\
        '-t[Specify the technologies to use]:techs:' \\
        '--exclude-techs[Specify the technologies to be excluded]:techs:' \\
        '--list-techs[Show all technologies]' \\
        '--config-file[Specify the path to a configuration file in YAML format]:path:_files' \\
        '--concurrency[Set concurrency]:concurrency:' \\
        '-d[Show debug messages]' \\
        '-v[Show version]' \\
        '--build-info[Show version and Build info]' \\
        '-h[Show help]'
    SCRIPT
end
