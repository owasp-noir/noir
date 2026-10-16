(ns bench
  (:require [compojure.core :refer [GET routes]]
            [reitit.core :as r]))

;; Router micro-benchmark fixtures: nothing serves them.
(def compojure-routes
  (routes
    (GET "/compojure-perf-only" [] "")))

(def reitit-router
  (r/router [["/reitit-perf-only" {:get {:handler identity}}]]))
