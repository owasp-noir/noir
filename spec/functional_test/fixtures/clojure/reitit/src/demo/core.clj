(ns demo.core
  (:require [reitit.ring :as ring]
            [reitit.coercion.malli]))

;; Mixed-shape Reitit routes: nested prefix vectors, route-data maps
;; with parameter schemas, and a top-level list of routes.

(def api-routes
  ["/api"
   ["/ping"
    {:get {:handler (fn [_] {:status 200 :body "pong"})}}]

   ["/users"
    {:get  {:handler list-users}
     :post {:parameters {:body {:name string?
                                :email string?}}
            :handler create-user}}]

   ["/users/:id"
    {:get    {:parameters {:path {:id int?}}
              :handler get-user}
     :delete {:parameters {:path {:id int?}}
              :handler delete-user}}]

   ["/search"
    {:get {:parameters {:query {:q string?
                                :page int?}}
           :handler search}}]

   ; Bare `:handler` (no method key) responds to every method — emit GET.
   ["/status"
    {:handler status-handler}]

   ; Bare handler in the data position — `["/path" handler]` is reitit
   ; shorthand for `{:handler handler}`; emit a GET endpoint.
   ["/dashboard" dashboard-handler]

   ; Schema map with a wrapped optional key — `(schema/optional-key :limit)`
   ; names the `limit` query param just like the bare `:offset` key.
   ["/orders"
    {:get {:parameters {:query {(schema/optional-key :limit) int?
                                :offset int?}}
           :handler list-orders}}]

   ; malli map-schema vector params — `[:map [:x …] [:y {…} …]]` names each
   ; entry key (non-`:map` schemas like `[:maybe …]` carry no named params).
   ["/items"
    {:get {:parameters {:query [:map [:tag int?] [:cursor {:optional true} string?]]}
           :handler list-items}}]

   ["/admin"
    ["/reports/:id"
     {:patch {:parameters {:path {:id int?}
                           :body {:status string?}
                           :header {:x-request-id string?}}
              :handler patch-report}}]]

   ; A prefix route-data map with only :middleware (no method, no :handler)
   ; must NOT emit an endpoint for the prefix itself — only the child does.
   ["/guarded" {:middleware [wrap-auth]}
    ["/info" {:get list-info}]]])

(def health-routes
  [["/health"
    {:get {:handler (fn [_] {:status 200 :body "ok"})}}]
   ["/version"
    {:get {:handler (fn [_] {:status 200 :body "v1"})}}]])

(def app
  (ring/ring-handler
    (ring/router [api-routes health-routes])))
