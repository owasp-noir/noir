(ns demo.compojure-routes
  (:require [compojure.core :refer [defroutes GET POST]]))

;; `#_` drops the next form at read time and `(comment ...)` never runs, so
;; only /compojure/live is a route here.
(defroutes app
  (GET "/compojure/live" [] "ok")
  #_(GET "/compojure/discarded" [] "no")
  #_ #_ (POST "/compojure/discarded-a" [] "no") (POST "/compojure/discarded-b" [] "no"))

(comment
  (GET "/compojure/in-comment" [] "no"))
