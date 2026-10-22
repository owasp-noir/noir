(ns app.compojure-app
  (:require [compojure.core :refer [defroutes GET]]))

(defroutes app-routes
  (GET "/compojure-live" [] "ok"))
