require "./locator_key"
require "./code_locator"

# Every slot in `CodeLocator`, declared once.
#
# The table below is the registry: the constants, the per-phase reset lists,
# and `spec/unit_test/models/locator_keys_spec.cr` are all generated from it,
# so a key cannot exist without a lifecycle and a lifecycle cannot be
# declared for a key nothing uses.
#
# Fields: {CONSTANT, name, :array | :single, lifecycle, owning subsystem}.
#
# Every one of these is written by the detector pass and drained during
# analysis, which is what `:detect_scoped` means — see
# `LocatorKey::Lifecycle`. The runtime-minted Express family below is the
# only `:analyze_scoped` slot.
module Noir::LocatorKeys
  DECLARATIONS = [
    {:ANDROID_ASSETLINKS, "android-assetlinks", :array, :detect_scoped, "detector/mobile/well_known"},
    {:ANDROID_MANIFEST, "android-manifest", :array, :detect_scoped, "detector/mobile/android"},
    {:APACHE_HTTPD_SPEC, "apache-httpd-spec", :array, :detect_scoped, "detector/specification/apache_httpd"},
    {:APISIX_JSON, "apisix-json", :array, :detect_scoped, "detector/specification/apisix"},
    {:APISIX_YAML, "apisix-yaml", :array, :detect_scoped, "detector/specification/apisix"},
    {:APPWRITE_CONFIG, "appwrite-config", :array, :detect_scoped, "detector/specification/appwrite"},
    {:ASYNCAPI_JSON, "asyncapi-json", :array, :detect_scoped, "detector/specification/asyncapi"},
    {:ASYNCAPI_YAML, "asyncapi-yaml", :array, :detect_scoped, "detector/specification/asyncapi"},
    {:AWS_CDK_SPEC, "aws-cdk-spec", :array, :detect_scoped, "detector/specification/aws_cdk"},
    {:AWS_CLOUDFORMATION_SPEC, "aws-cloudformation-spec", :array, :detect_scoped, "detector/specification/aws_cloudformation"},
    {:AZURE_FUNCTIONS_SPEC, "azure-functions-spec", :array, :detect_scoped, "detector/specification/azure_functions"},
    {:BRUNO_BRU, "bruno-bru", :array, :detect_scoped, "detector/specification/bruno"},
    {:BURP_SITEMAP, "burp-sitemap", :array, :detect_scoped, "detector/specification/burp"},
    {:CADDY_SPEC, "caddy-spec", :array, :detect_scoped, "detector/specification/caddy"},
    {:CAIDO_JSON, "caido-json", :array, :detect_scoped, "detector/specification/caido"},
    {:CLOUDFLARE_WRANGLER_SPEC, "cloudflare-wrangler-spec", :array, :detect_scoped, "detector/specification/cloudflare_wrangler"},
    {:CS_APINET_MVC_ROUTECONFIG, "cs-apinet-mvc-routeconfig", :single, :detect_scoped, "detector/csharp/aspnet_mvc"},
    {:DIRECTUS_SNAPSHOT, "directus-snapshot", :array, :detect_scoped, "detector/specification/directus"},
    {:ENVOY_JSON, "envoy-json", :array, :detect_scoped, "detector/specification/envoy"},
    {:ENVOY_YAML, "envoy-yaml", :array, :detect_scoped, "detector/specification/envoy"},
    {:GRAPHQL_SDL, "graphql-sdl", :array, :detect_scoped, "detector/specification/graphql_sdl"},
    {:GRPC_PROTO, "grpc-proto", :array, :detect_scoped, "detector/specification/grpc"},
    {:HAR_PATH, "har-path", :array, :detect_scoped, "detector/specification/har"},
    {:HASURA_REST_ENDPOINTS, "hasura-rest-endpoints", :array, :detect_scoped, "detector/specification/hasura"},
    {:HASURA_TABLES, "hasura-tables", :array, :detect_scoped, "detector/specification/hasura"},
    {:HTTP_FILE, "http-file", :array, :detect_scoped, "detector/specification/http_file"},
    {:INSOMNIA_JSON, "insomnia-json", :array, :detect_scoped, "detector/specification/insomnia"},
    {:INSOMNIA_YAML, "insomnia-yaml", :array, :detect_scoped, "detector/specification/insomnia"},
    {:IOS_AASA, "ios-aasa", :array, :detect_scoped, "detector/mobile/well_known"},
    {:IOS_ENTITLEMENTS, "ios-entitlements", :array, :detect_scoped, "detector/mobile/ios"},
    {:IOS_INFO_PLIST, "ios-info-plist", :array, :detect_scoped, "detector/mobile/ios"},
    {:ISTIO_VIRTUALSERVICE_SPEC, "istio-virtualservice-spec", :array, :detect_scoped, "detector/specification/istio_virtualservice"},
    {:K8S_GATEWAY_API_SPEC, "k8s-gateway-api-spec", :array, :detect_scoped, "detector/specification/k8s_gateway_api"},
    {:K8S_INGRESS_SPEC, "k8s-ingress-spec", :array, :detect_scoped, "detector/specification/k8s_ingress"},
    {:KAMAL_SPEC, "kamal-spec", :array, :detect_scoped, "detector/specification/kamal"},
    {:KONG_SPEC, "kong-spec", :array, :detect_scoped, "detector/specification/kong"},
    {:MITMPROXY_PATH, "mitmproxy-path", :array, :detect_scoped, "detector/specification/mitmproxy"},
    {:NETLIFY_REDIRECTS, "netlify-redirects", :array, :detect_scoped, "detector/specification/netlify"},
    {:NETLIFY_TOML, "netlify-toml", :array, :detect_scoped, "detector/specification/netlify"},
    {:NGINX_SPEC, "nginx-spec", :array, :detect_scoped, "detector/specification/nginx"},
    {:OAS3_JSON, "oas3-json", :array, :detect_scoped, "detector/specification/oas3"},
    {:OAS3_YAML, "oas3-yaml", :array, :detect_scoped, "detector/specification/oas3"},
    {:ODATA_SPEC, "odata-spec", :array, :detect_scoped, "detector/specification/odata"},
    {:OPENRPC_JSON, "openrpc-json", :array, :detect_scoped, "detector/specification/openrpc"},
    {:PAYLOAD_COLLECTION, "payload-collection", :array, :detect_scoped, "detector/specification/payload_cms"},
    {:PAYLOAD_CONFIG, "payload-config", :array, :detect_scoped, "detector/specification/payload_cms"},
    {:PAYLOAD_GLOBAL, "payload-global", :array, :detect_scoped, "detector/specification/payload_cms"},
    {:POSTMAN_JSON, "postman-json", :array, :detect_scoped, "detector/specification/postman"},
    {:RAML_SPEC, "raml-spec", :array, :detect_scoped, "detector/specification/raml"},
    {:SERVERLESS_FRAMEWORK_SPEC, "serverless-framework-spec", :array, :detect_scoped, "detector/specification/serverless_framework"},
    {:SMITHY_SPEC, "smithy-spec", :array, :detect_scoped, "detector/specification/smithy"},
    {:STRAPI_ROUTES, "strapi-routes", :array, :detect_scoped, "detector/specification/strapi"},
    {:STRAPI_SCHEMA, "strapi-schema", :array, :detect_scoped, "detector/specification/strapi"},
    {:SUPABASE_CONFIG, "supabase-config", :array, :detect_scoped, "detector/specification/supabase"},
    {:SUPABASE_MIGRATION, "supabase-migration", :array, :detect_scoped, "detector/specification/supabase"},
    {:SWAGGER_JSON, "swagger-json", :array, :detect_scoped, "detector/specification/oas2"},
    {:SWAGGER_YAML, "swagger-yaml", :array, :detect_scoped, "detector/specification/oas2"},
    {:TERRAFORM_SPEC, "terraform-spec", :array, :detect_scoped, "detector/specification/terraform"},
    {:TRAEFIK_SPEC, "traefik-spec", :array, :detect_scoped, "detector/specification/traefik"},
    {:TYPESPEC_SPEC, "typespec-spec", :array, :detect_scoped, "detector/specification/typespec"},
    {:VERCEL_SPEC, "vercel-spec", :array, :detect_scoped, "detector/specification/vercel"},
    {:WSDL_SPEC, "wsdl-spec", :array, :detect_scoped, "detector/specification/wsdl"},
    {:ZAP_SITES_TREE, "zap-sites-tree", :array, :detect_scoped, "detector/specification/zap_sites_tree"},
  ]

  {% begin %}
    {% for d in DECLARATIONS %}
      {% t = d[2] == :array ? "Array(String)".id : "String".id %}
      {{ d[0].id }} = ::Noir::LocatorKey({{ t }}).new(
        {{ d[1] }},
        ::Noir::LocatorKey::Lifecycle::{{ d[3].id.camelcase }},
        {{ d[4] }})
    {% end %}

    # The array literals are what force the constants above into existence.
    # Do not "simplify" this into per-constant registration side effects:
    # Crystal may elide an unused constant's initializer, and the reset
    # lists would silently come up short.
    ARRAY_KEYS = [
      {% for d in DECLARATIONS %}{% if d[2] == :array %}{{ d[0].id }},{% end %}{% end %}
    ] of ::Noir::LocatorKey(Array(String))

    SINGLE_KEYS = [
      {% for d in DECLARATIONS %}{% if d[2] == :single %}{{ d[0].id }},{% end %}{% end %}
    ] of ::Noir::LocatorKey(String)
  {% end %}

  # Runtime-minted key family: `express_router_prefix:<file>[:<function>]`.
  # Written during analysis by the Express router-mount scanner and by Koa,
  # read by the shared JS route extractor.
  EXPRESS_ROUTER_PREFIX = ::Noir::LocatorKeyNamespace.new(
    "express_router_prefix",
    ::Noir::LocatorKey::Lifecycle::AnalyzeScoped,
    "analyzer/javascript/express")

  NAMESPACES = [EXPRESS_ROUTER_PREFIX]
end
