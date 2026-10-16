(ns app.pedestal-handlers
  (:require [io.pedestal.http.route.definition.table :as table]))

;; Throwaway test routes: nothing serves them.
(defn test-handler [_request] {:status 200 :body "ok"})

(def test-routes
  (table/table-routes
    [["/pedestal-test-only" :get test-handler :route-name :test-only]]))
