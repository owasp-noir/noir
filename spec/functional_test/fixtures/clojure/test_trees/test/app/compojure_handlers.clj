(ns app.compojure-handlers
  (:require [compojure.core :refer [defroutes GET]]))

;; Throwaway test handler: nothing serves it.
(defroutes test-routes
  (GET "/compojure-test-only" [] "ok"))
