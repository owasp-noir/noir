(ns demo.core
  (:require [io.pedestal.http :as http]
            [io.pedestal.http.route :as route]
            [io.pedestal.http.route.definition :refer [defroutes]]
            [io.pedestal.http.route.definition.table :as table]
            [clj-http.client :as client]
            [clojure.tools.logging :as log]))

;; Regression guard: a namespaced verb whose first string is a full URL or a
;; log message is an HTTP-client / logging call, NOT a route helper — it must
;; not emit a phantom endpoint.
(defn call-upstream [_request]
  (log/trace "writing event to stream")
  (client/post "http://localhost:8888/api" {:body "x"})
  (client/get "https://example.com/health" {}))

(defn home-page [_request] {:status 200 :body "home"})
(defn list-users [_request] {:status 200 :body "users"})
(defn create-user [_request] {:status 201 :body "created"})
(defn get-user [_request] {:status 200 :body "user"})
(defn update-user [_request] {:status 200 :body "updated"})
(defn delete-user [_request] {:status 204 :body ""})
(defn get-file [_request] {:status 200 :body "file"})
(defn list-orders [_request] {:status 200 :body "orders"})
(defn update-order [_request] {:status 200 :body "order"})
(defn create-report [_request] {:status 201 :body "report"})
(defn show-report [_request] {:status 200 :body "report"})
(defn status [_request] {:status 200 :body "ok"})
(defn delete-job [_request] {:status 204 :body ""})
(defn health-handler [_request] {:status 200 :body "ok"})
(defn create-order [_request] {:status 201 :body "order"})
(defn query-handler [_request] {:status 200 :body "query"})
(defn expanded-handler [_request] {:status 200 :body "expanded"})
(defn verbose-child-handler [_request] {:status 200 :body "verbose child"})
(defn verbose-helper-handler [_request] {:status 200 :body "verbose helper"})
(defn constrained-search [_request] {:status 200 :body "search"})

(defroutes classic-routes
  [[["/" {:get home-page}
     ^:interceptors [http/html-body]
     ["/users" {:get list-users :post create-user}
      ["/:id" {:get get-user :put update-user :delete delete-user}]]
     ["/files/*path" {:get get-file}]]]])

(def table-routes
  (table/table-routes
    {:context "/api"}
    [["/orders" :get list-orders :route-name :orders]
     ["/orders/:order-id" :patch update-order]
     {:context "/admin"}
     ["/reports" :post create-report]
     ["/reports/:id" :get show-report]]))

(def map-routes
  {:path "/map"
   :verbs {:get status}
   :children [{:path "/status"
               :verbs {:get status}}
              {:path "/jobs/:id"
               :verbs {:delete delete-job}}]})

(def helper-routes
  [(route/get "/health" [] health-handler)
   (route/post "/api/orders" [] create-order)])

(def query-verb-routes
  (table/table-routes
    {:verbs #{:get :query}}
    [["/custom-query" :query query-handler]]))

(def expanded-route-maps
  [{:path "/expanded"
    :method :get
    :route-name :expanded
    :interceptors [expanded-handler]}])

(def verbose-parent-routes
  [{:path "/verbose-parent"
    :children [{:path "/child"
                :verbs {:get verbose-child-handler}}
               (route/get "/health" [] verbose-helper-handler)]}])

(def constrained-child-routes
  [["/search"
    [^:constraints {:q #".+"}
     {:get constrained-search}]]])

(def service
  {::http/routes [classic-routes table-routes map-routes helper-routes query-verb-routes expanded-route-maps verbose-parent-routes constrained-child-routes]})
