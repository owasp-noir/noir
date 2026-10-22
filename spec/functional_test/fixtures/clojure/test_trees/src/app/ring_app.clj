(ns app.ring-app
  (:require [ring.adapter.jetty :as jetty]))

(defn handler [req]
  (case [(:request-method req) (:uri req)]
    [:get "/ring-live"] {:status 200 :body "ok"}
    {:status 404}))
