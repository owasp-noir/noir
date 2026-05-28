(ns demo.core
  (:require [io.pedestal.http :as http]
            [io.pedestal.http.route :as route]
            [io.pedestal.http.route.definition :refer [defroutes]]
            [io.pedestal.http.route.definition.table :as table]))

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

(def service
  {::http/routes [classic-routes table-routes map-routes helper-routes]})
