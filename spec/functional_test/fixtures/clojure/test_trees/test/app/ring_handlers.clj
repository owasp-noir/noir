(ns app.ring-handlers
  (:require [ring.adapter.jetty :as jetty]))

;; Throwaway test handler: nothing serves it.
(defn test-handler [req]
  (case [(:request-method req) (:uri req)]
    [:get "/ring-test-only"] {:status 200 :body "ok"}
    {:status 404}))
