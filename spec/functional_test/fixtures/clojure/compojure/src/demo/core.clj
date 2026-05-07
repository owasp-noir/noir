(ns demo.core
  (:require [compojure.core :refer [defroutes GET POST DELETE ANY context routes]]))

(defroutes app-routes
  (GET "/" []
    "home")

  (GET "/users/:id" [id]
    {:id id})

  (GET "/search" [q page]
    {:q q :page page})

  (context "/api" []
    (POST "/users" request
      request)

    (context "/admin" []
      (DELETE "/users/:id" [id force]
        {:id id :force force}))

    (ANY "/ping" []
      "pong"))

  (routes
    (GET "/health" []
      "ok")))
