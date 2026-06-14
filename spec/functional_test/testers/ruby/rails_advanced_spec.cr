require "../../func_spec.cr"

# Regression test for #1358: Rails routes.rb DSL features (namespace, scope,
# nested resources, member/collection, only:/except:, controller: override,
# root, devise_for, mount, hash-rocket form) must be parsed correctly. Also
# covers #1359: custom controller actions (member/collection + `to:`/=>
# controller#action) must surface with their per-action params.
expected_endpoints = [
  # root "home#index"
  Endpoint.new("/", "GET"),

  # Local string variable + `#{var}` interpolation: the analyzer
  # captures `base_c_route = "..."` and substitutes the literal in
  # subsequent route declarations. Discourse's chat plugin
  # depends on this resolution to avoid phantom `/#{base_c_route}/...`
  # entries.
  Endpoint.new("/c/:channel_title/:channel_id/:message_id", "GET"),
  Endpoint.new("/c/:channel_title/:channel_id/messages", "POST"),

  # `#{ENV.fetch('URL_COMPONENT', 'bb')}` interpolation embeds quotes; the
  # path must be captured whole (placeholdered), not truncated mid-quote.
  Endpoint.new("/{ENV.fetch}/:area", "GET"),

  # namespace :admin do resources :reports end
  Endpoint.new("/admin/reports", "GET"),
  Endpoint.new("/admin/reports/1", "GET"),
  Endpoint.new("/admin/reports", "POST"),
  Endpoint.new("/admin/reports/1", "PUT"),
  Endpoint.new("/admin/reports/1", "PATCH"),
  Endpoint.new("/admin/reports/1", "DELETE"),

  # member/collection actions on namespaced resource. #1359: action-scoped
  # headers must surface on the custom-action endpoint (previously dropped
  # because the controller scan only switched action context on 5 REST names).
  Endpoint.new("/admin/refunds/1/change_status", "POST", [
    Param.new("X-Refund-Reason", "", "header"),
    Param.new("status", "", "form"),
  ]),
  # DELETE custom action — no shared body params, only the action's headers.
  Endpoint.new("/admin/refunds/1/purge", "DELETE", [
    Param.new("X-Confirm", "", "header"),
  ]),
  # `permit("note", "kind")` (string form) and member POST verb.
  Endpoint.new("/admin/refunds/1/update_metadata", "POST", [
    Param.new("note", "", "form"),
    Param.new("kind", "", "form"),
  ]),
  Endpoint.new("/admin/refunds/new_list", "GET", [
    Param.new("X-Page", "", "header"),
  ]),

  # Namespaced `to: "ctrl#action"` resolves against `admin/monitor_controller.rb`,
  # not the root-level `monitor_controller.rb`. Also exercises `params["id"]`
  # (string-key form).
  Endpoint.new("/admin/monitor/heartbeat", "GET", [
    Param.new("X-Heartbeat", "", "header"),
    Param.new("id", "", "query"),
  ]),

  # Keyword-block guard: route inside `if Rails.env.test?` and the route
  # after the `end` both stay under `/admin`.
  Endpoint.new("/admin/debug/echo", "GET"),
  Endpoint.new("/admin/after_conditional", "GET"),

  # Parenthesized namespace with path override keeps the controller namespace
  # while changing the URL prefix.
  Endpoint.new("/sekret/reports", "GET"),
  Endpoint.new("/sekret/reports/1", "GET"),

  # scope module/path variants resolve controller params through admin/.
  Endpoint.new("/backoffice/heartbeat", "GET", [
    Param.new("X-Heartbeat", "", "header"),
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/module_ping", "GET", [
    Param.new("X-Heartbeat", "", "header"),
    Param.new("id", "", "query"),
  ]),

  # controller block + action-symbol hash rocket.
  Endpoint.new("/controller_ping", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),

  # scope :api do resources :items, only: [:index, :show] end
  Endpoint.new("/api/items", "GET"),
  Endpoint.new("/api/items/1", "GET"),

  # scope path: "internal" do resources :statements, except: [:destroy] end
  Endpoint.new("/internal/statements", "GET"),
  Endpoint.new("/internal/statements/1", "GET"),
  Endpoint.new("/internal/statements", "POST"),
  Endpoint.new("/internal/statements/1", "PUT"),
  Endpoint.new("/internal/statements/1", "PATCH"),

  # resources :scans, controller: "billing/scans", only: [:index]
  Endpoint.new("/scans", "GET"),

  # Multiline options and %i lists.
  Endpoint.new("/legacy_posts", "GET"),
  Endpoint.new("/legacy_posts/1", "GET"),

  # Inline custom resource scopes: collection, implicit member, and new.
  Endpoint.new("/refunds/summary", "GET", [
    Param.new("X-Summary", "", "header"),
  ]),
  Endpoint.new("/refunds/1/preview", "GET", [
    Param.new("X-Preview", "", "header"),
  ]),
  Endpoint.new("/refunds/new/template", "GET", [
    Param.new("X-Template", "", "header"),
  ]),
  Endpoint.new("/refunds/inline_summary", "GET", [
    Param.new("X-Inline-Summary", "", "header"),
  ]),
  Endpoint.new("/refunds/1/inline_preview", "POST", [
    Param.new("X-Inline-Preview", "", "header"),
  ]),

  # Rails concerns: `concern :commentable do resources :comments end`
  # should not emit top-level `/comments` routes, and applying the concern
  # with `resources :posts, concerns: :commentable` should emit nested
  # comments and preserve nested resources inside the concern.
  Endpoint.new("/posts", "GET"),
  Endpoint.new("/posts/1", "GET"),
  Endpoint.new("/posts", "POST"),
  Endpoint.new("/posts/1", "PUT"),
  Endpoint.new("/posts/1", "PATCH"),
  Endpoint.new("/posts/1", "DELETE"),
  Endpoint.new("/posts/1/comments", "GET"),
  Endpoint.new("/posts/1/comments/1", "GET"),
  Endpoint.new("/posts/1/comments/1/likes", "GET"),
  Endpoint.new("/posts/1/comments/1/likes/1", "GET"),

  # hash-rocket and to: forms. #1359: `=> "ctrl#action"` / `to: "ctrl#action"`
  # resolves the controller and attaches the action's params.
  Endpoint.new("/up", "GET", [
    Param.new("X-Health", "", "header"),
  ]),
  Endpoint.new("/ping", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),
  Endpoint.new("/legacy_ping", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),

  # Optional route segments `(.:format)` / `(/:section)` peeled to the
  # required base path (nested + middle-segment `//` collapse).
  Endpoint.new("/feed", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),
  Endpoint.new("/report/rss", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),
  Endpoint.new("/localized_ping", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),

  # `%w[browse annotate].each do |action|` unrolls to one route per literal
  # element with `#{action}` substituted — never leaking raw Ruby or a
  # fabricated `{action}` path param into the URL.
  Endpoint.new("/repo/:id/browse", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),
  Endpoint.new("/repo/:id/annotate", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),

  # devise_for :users — sample of generated routes
  Endpoint.new("/users/sign_in", "GET"),
  Endpoint.new("/users/sign_in", "POST"),
  Endpoint.new("/users/sign_out", "DELETE"),
  Endpoint.new("/users/sign_up", "GET"),
  Endpoint.new("/users", "POST"),
  Endpoint.new("/users/password/new", "GET"),

  # mount Sidekiq::Web, at: "/sidekiq"
  Endpoint.new("/sidekiq", "GET"),

  # Parenthesized/multiline explicit route and Rails draw files.
  Endpoint.new("/split", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),
  Endpoint.new("/drawn/health", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),
  Endpoint.new("/v1/drawn/health", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),
  Endpoint.new("/v2/drawn/health", "GET", [
    Param.new("X-Ping", "", "header"),
  ]),
]

# Locking the total count ensures only:/except: filters drop the expected
# endpoints (e.g. no POST /api/items, no DELETE /internal/statements, no
# /scans/1) and devise_for emits its full route set.
total_endpoints = 1 +  # root
                  2 +  # `#{base_c_route}` interpolation resolved to 2 routes
                  1 +  # `#{ENV.fetch(...)}` nested-quote interpolation placeholder
                  6 +  # admin/reports
                  4 +  # admin/refunds member (change_status, purge, update_metadata) + collection (new_list)
                  1 +  # admin/monitor/heartbeat (namespaced `to:`)
                  2 +  # admin debug/echo (inside if-block) + after_conditional (keeps /admin)
                  2 +  # namespace path override reports
                  2 +  # scope module/path explicit routes
                  1 +  # controller block route
                  2 +  # api/items only:[index,show]
                  5 +  # internal/statements except:[destroy]
                  1 +  # /scans only:[index] via controller override
                  2 +  # multiline resources options
                  5 +  # inline collection/member/new custom routes
                  6 +  # posts
                  4 +  # posts/1/comments + nested likes from concern
                  3 +  # /up + /ping + legacy string-via match
                  3 +  # optional-segment routes /feed + /report/rss + optional scope
                  2 +  # %w[browse annotate].each unrolled to /repo/:id/browse + /annotate
                  20 + # devise_for :users
                  1 +  # mount sidekiq
                  1 +  # multiline parenthesized get
                  3    # draw :external at root and under two scopes

FunctionalTester.new("fixtures/ruby/rails_advanced/", {
  :techs     => 1,
  :endpoints => total_endpoints,
}, expected_endpoints).perform_tests
