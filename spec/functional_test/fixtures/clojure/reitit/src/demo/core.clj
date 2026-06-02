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
