(ns app.reitit-app
  (:require [reitit.ring :as ring]))

(def app
  (ring/ring-handler
    (ring/router
      [["/reitit-live" {:get {:handler (fn [_] {:status 200 :body "ok"})}}]])))
