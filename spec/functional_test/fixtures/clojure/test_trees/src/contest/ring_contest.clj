(ns contest.ring-contest
  (:require [ring.adapter.jetty :as jetty]))

;; `contest/` and `latest/` are not test trees: only a whole `test/` segment is.
(defn handler [req]
  (case [(:request-method req) (:uri req)]
    [:get "/ring-contest-live"] {:status 200 :body "ok"}
    {:status 404}))
