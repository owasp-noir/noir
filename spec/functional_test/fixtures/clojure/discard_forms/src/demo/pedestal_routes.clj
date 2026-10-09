(ns demo.pedestal-routes
  (:require [io.pedestal.http.route :as route]))

(def routes
  (route/expand-routes
    #{["/pedestal/live" :get `home]
      #_["/pedestal/off" :get `off]}))

(comment
  (route/expand-routes #{["/pedestal/in-comment" :get `x]}))
