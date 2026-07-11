(ns myapp.handler
  (:require [ring.adapter.jetty :refer [run-jetty]]
            [myapp.config :as config]))

(defn app [request]
  {:status 200 :body (str "db=" config/db-url)})

(defn -main [& args]
  (run-jetty app {:port 3000}))
