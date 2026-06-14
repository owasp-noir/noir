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

;; Bare-string `case`/`condp` dispatch directly on the URI (no method): each
;; key-position `/`-string is a GET route. A `case` on any non-`(:uri …)`
;; value (here `(:server-name req)`) must NOT emit phantom routes.
(defn uri-handler [req]
  (case (:uri req)
    "/about"       (about-page)
    "/contact/:id" (contact-page req)
    (not-found)))

(defn uri-condp-handler [req]
  (condp = (:uri req)
    "/status"            {:status 200}
    ("/up" "/readiness") {:status 200}
    (default)))

(defn host-router [req]
  (case (:server-name req)
    "/admin-host" (admin-app req)
    (main-app req)))

(defn -main [& _args]
  (jetty/run-jetty handler {:port 3000}))
