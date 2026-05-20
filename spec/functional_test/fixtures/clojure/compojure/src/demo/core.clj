(ns demo.core
  (:require [compojure.core :refer [defroutes GET POST DELETE ANY context routes]]))

(defroutes app-routes
  (GET "/" []
    "home")

  (GET "/users/:id" [id]
    {:id id})

  (GET "/search" [q page]
    {:q q :page page})

  ; `:as request` should NOT emit `as` or `request` as query params.
  (GET "/feed" [cursor :as request]
    {:cursor cursor})

  ; `& rest` rest-binding should NOT emit `rest` as a query param.
  (GET "/tags" [tag & rest]
    {:tag tag})

  ; Map destructuring of the request map — `:keys` should be lifted (한글 주석도 OK).
  (POST "/notes" {:keys [title body]}
    {:title title :body body})

  ; Namespace-qualified `:my.ns/keys` should still lift bound symbols.
  (POST "/comments" {:my.ns/keys [author message]}
    {:author author :message message})

  ; `:as` followed by a destructuring map: keys inside bind the request map,
  ; NOT query params. Only `id` and `q` should be lifted.
  (GET "/profile/:id" [id q :as {:keys [headers]}]
    {:id id :q q})

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
