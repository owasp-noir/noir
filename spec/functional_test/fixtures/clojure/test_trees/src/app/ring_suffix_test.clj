(ns app.ring-suffix-test
  (:require [ring.adapter.jetty :as jetty]))

;; `foo_test.clj` holds the tests for `app.foo`: nothing serves it.
(defn handler [req]
  (case [(:request-method req) (:uri req)]
    [:get "/ring-suffix-only"] {:status 200 :body "ok"}
    {:status 404}))
