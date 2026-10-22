(ns app.pedestal-app
  (:require [io.pedestal.http.route.definition.table :as table]))

(defn live-handler [_request] {:status 200 :body "ok"})

(def routes
  (table/table-routes
    [["/pedestal-live" :get live-handler :route-name :live]]))
