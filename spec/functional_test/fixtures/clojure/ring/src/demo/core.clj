(ns demo.core
  (:require [ring.adapter.jetty :as jetty]))

;; `case` dispatch on [method uri] pairs — the most common Ring-only pattern.
(defn handler [req]
  (case [(:request-method req) (:uri req)]
    [:get  "/users"]  (list-users)
    [:post "/users"]  (create-user req)
    [:get  "/health"] {:status 200 :body "ok"}
    [:any  "/ping"]   {:status 200 :body "pong"}
    {:status 404}))

;; `cond` dispatch — `and` clauses combine method + uri equality.
(defn cond-handler [req]
  (cond
    (and (= :get (:request-method req))
         (= "/metrics" (:uri req)))
    {:status 200 :body "metrics"}

    (and (= :delete (:request-method req))
         (= "/sessions" (:uri req)))
    {:status 204}

    ;; URI-only branch defaults to GET.
    (= "/version" (:uri req))
    {:status 200 :body "v1"}

    :else
    {:status 404}))

(defn -main [& _args]
  (jetty/run-jetty handler {:port 3000}))
