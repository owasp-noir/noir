(ns demo.core
  (:require [io.pedestal.http :as http]
            [io.pedestal.http.route :as route]
            [io.pedestal.http.route.definition :refer [defroutes]]
            [io.pedestal.http.route.definition.table :as table]
            [ring.util.response :as response]))

(defn ^:private list-users [request]
  (response/ok (user.service/list request)))

(defn create-user [request]
  (audit.log/write! "create" request)
  (response/created "/users/1" (user.service/create! request)))

(defn health-handler [_request]
  (response/ok (health.service/check)))

(defroutes classic-routes
  [[["/users" {:get #'list-users :post `create-user}]]])

(def helper-routes
  [(route/get "/health" [] #'health-handler)])

(def table-routes
  (table/table-routes
    {:context "/api"}
    [["/inline" :get (fn [request]
                      (response/ok (inline.service/run request)))]]))

(def service
  {::http/routes [classic-routes helper-routes table-routes]})
