(ns app.reitit-handlers
  (:require [reitit.ring :as ring]))

;; Throwaway test router: nothing serves it.
(def test-app
  (ring/ring-handler
    (ring/router
      [["/reitit-test-only" {:get {:handler (fn [_] {:status 200 :body "ok"})}}]])))
