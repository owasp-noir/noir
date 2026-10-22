(ns demo.reitit-routes
  (:require [reitit.ring :as ring]))

(def router
  (ring/router
    [["/reitit/live" {:get handler}]
     #_["/reitit/off" {:get handler}]]))

(comment
  (ring/router [["/reitit/in-comment" {:get handler}]]))
