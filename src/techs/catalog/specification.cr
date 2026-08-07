# NoirTechs catalog: spec, schema and infrastructure-config formats.
# Entry shape and helpers live in src/techs/techs.cr, which
# merges every Catalog constant into NoirTechs::TECHS.
module NoirTechs::Catalog
  SPECIFICATION = {
    :bruno => {
      :format    => ["BRU"],
      :similar   => ["bruno", "bru"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
    :burp => {
      :format    => ["XML"],
      :similar   => ["burp", "burpsuite", "burp-suite", "burp_suite", "burp-sitemap"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :caido => {
      :format    => ["JSON"],
      :similar   => ["caido", "caido-export", "caido_export"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :har => {
      :format    => ["JSON"],
      :similar   => ["har"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :http_file => {
      :format    => ["HTTP", "REST"],
      :similar   => ["http_file", "rest-client", "rest_client", "http-client", "http_client", ".http", ".rest"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
    :mitmproxy => {
      :format    => ["TNETSTRING"],
      :similar   => ["mitmproxy", "mitm", "mitmdump", "flow", "flows"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    # The analyzer walks the exported node tree and emits `url` + `method`,
    # plus the `data` string split into `form` params. The query string is
    # dropped with the rest of the URI (only `uri.path` is kept), and the
    # export carries no header or cookie record — hence body-only params.
    #
    # No bare `"zap"` alias: `zig_zap` already owns it, and a duplicate
    # would resolve by TECHS iteration order rather than by intent.
    :zap_sites_tree => {
      :format    => ["YAML"],
      :similar   => ["zap_sites_tree", "zap-sites-tree", "zap-sitemap", "zap_sitemap", "zaproxy", "owasp-zap"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
    :apache_httpd => {
      :format    => ["CONF"],
      :similar   => ["apache", "apache httpd", "httpd", "htaccess", "apache2"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :apisix => {
      :format    => ["JSON", "YAML"],
      :similar   => ["apisix", "apache apisix", "apache-apisix", "apache_apisix"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => true,
          :cookie => false,
        },
      },
    },
    :appwrite => {
      :format    => ["JSON"],
      :similar   => ["appwrite", "appwrite-config", "appwrite_config", "appwrite.json"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
    :aws_cdk => {
      :format    => ["TS", "JS", "PY"],
      :similar   => ["aws cdk", "aws-cdk-lib", "@aws-cdk", "cdk", "aws_cdk"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :aws_cloudformation => {
      :format    => ["YAML", "JSON"],
      :similar   => ["aws cloudformation", "aws sam", "cloudformation", "sam", "template.yaml", "template.yml", "aws::serverless::function", "aws::apigateway::resource"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :azure_functions => {
      :format    => ["JSON"],
      :similar   => ["azure functions", "azure-functions", "function.json", "azure"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :caddy => {
      :format    => ["CADDYFILE", "JSON"],
      :similar   => ["caddy", "caddyfile", "caddy.json"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :cloudflare_wrangler => {
      :format    => ["TOML", "JSON"],
      :similar   => ["cloudflare", "cloudflare workers", "wrangler", "wrangler.toml", "wrangler.json", "wrangler.jsonc"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :directus => {
      :format    => ["YAML", "JSON"],
      :similar   => ["directus", "directus-snapshot", "directus_snapshot", "directus schema"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
    :hasura => {
      :format    => ["YAML"],
      :similar   => ["hasura", "hasura-metadata", "hasura_metadata", "hasura graphql engine"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
    :k8s_gateway_api => {
      :format    => ["YAML"],
      :similar   => ["kubernetes gateway api", "k8s gateway api", "httproute", "gateway.networking.k8s.io"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :istio_virtualservice => {
      :format    => ["YAML"],
      :similar   => ["istio", "virtualservice", "networking.istio.io"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :k8s_ingress => {
      :format    => ["YAML"],
      :similar   => ["kubernetes ingress", "k8s ingress", "kubernetes.io/ingress", "networking.k8s.io/v1"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :kamal => {
      :format    => ["YAML"],
      :similar   => ["kamal", "kamal deploy", "kamal-deploy", "kamal proxy", "deploy.yml"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :kong => {
      :format    => ["YAML"],
      :similar   => ["kong", "kong declarative", "deck", "kong ingress controller", "kic"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :oas2 => {
      :format    => ["JSON", "YAML"],
      :similar   => ["oas 2.0", "oas_2_0", "swagger 2.0", "swagger_2_0", "swagger"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :oas3 => {
      :format    => ["JSON", "YAML"],
      :similar   => ["oas 3.0", "oas_3_0"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :asyncapi => {
      :format    => ["JSON", "YAML"],
      :similar   => ["asyncapi", "async-api", "async_api"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
    :openrpc => {
      :format    => ["JSON"],
      :similar   => ["openrpc", "open-rpc", "open_rpc", "jsonrpc", "json-rpc", "json_rpc"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
    :grpc => {
      :format    => ["PROTOBUF"],
      :similar   => ["grpc", "protobuf", "proto", "grpc-gateway"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
    :envoy => {
      :format    => ["JSON", "YAML"],
      :similar   => ["envoy", "envoy-proxy", "envoy_proxy", "istio-envoy"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    # `:graphql` used to sit here with no analyzer and no detector behind it
    # — a catalog entry that advertised support nothing could deliver, and
    # whose `"graphql"` / `".graphql"` aliases resolved to that dead end
    # instead of to the analyzer that really reads those files. The aliases
    # moved onto `graphql_sdl`, whose detector already claims `.graphql`
    # (see `Detector::Specification::GraphqlSdl#applicable?`), so `-t
    # graphql` now selects a tech that produces endpoints.
    :graphql_sdl => {
      :format    => ["GRAPHQL_SDL"],
      :similar   => ["graphql_sdl", "graphql-sdl", "graphql_schema", ".graphqls", "graphql", ".graphql"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
    :insomnia => {
      :format    => ["JSON", "YAML"],
      :similar   => ["insomnia", "insomnia collection", "insomnia export"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
    :nginx => {
      :format    => ["CONF"],
      :similar   => ["nginx", "nginx.conf", "sites-enabled", "conf.d"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :netlify => {
      :format    => ["TXT", "TOML"],
      :similar   => ["netlify", "_redirects", "netlify.toml"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :postman => {
      :format    => ["JSON"],
      :similar   => ["postman", "postman collection"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
    :raml => {
      :format    => ["YAML"],
      :similar   => ["raml"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :payload_cms => {
      :format    => ["TS", "JS"],
      :similar   => ["payload", "payloadcms", "payload-cms", "payload_cms", "payload cms"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
    :serverless_framework => {
      :format    => ["YAML", "JSON"],
      :similar   => ["serverless framework", "serverless.yml", "serverless.yaml", "serverless.json", "aws lambda"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :strapi => {
      :format    => ["JSON", "TS", "JS"],
      :similar   => ["strapi", "strapi5", "strapi-cms", "strapi_cms", "strapi v4", "strapi v5"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
    :supabase => {
      :format    => ["SQL"],
      :similar   => ["supabase", "postgrest", "supabase-migrations", "supabase_migrations", "pgrst"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
    :smithy => {
      :format    => ["SMITHY"],
      :similar   => ["smithy", "smithy-idl"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
    :terraform => {
      :format    => ["TF", "JSON"],
      :similar   => ["terraform", "tf", "hcl", "opentofu", "tofu", "aws_api_gateway", "aws_apigatewayv2", "aws_apigatewayv2_route"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :traefik => {
      :format    => ["YAML", "TOML"],
      :similar   => ["traefik", "traefik dynamic config", "ingressroute"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :typespec => {
      :format    => ["TYPESPEC"],
      :similar   => ["typespec", "tsp", "cadl"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => true,
          :cookie => true,
        },
      },
    },
    :vercel => {
      :format    => ["JSON"],
      :similar   => ["vercel", "vercel.json", "now.json"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => false,
          :header => false,
          :cookie => false,
        },
      },
    },
    :wsdl => {
      :format    => ["XML"],
      :similar   => ["wsdl", "soap"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => false,
          :path   => false,
          :body   => true,
          :header => true,
          :cookie => false,
        },
      },
    },
    :odata => {
      :format    => ["XML"],
      :similar   => ["odata", "edmx", "csdl"],
      :supported => {
        :endpoint => true,
        :method   => true,
        :params   => {
          :query  => true,
          :path   => true,
          :body   => true,
          :header => false,
          :cookie => false,
        },
      },
    },
  }
end
