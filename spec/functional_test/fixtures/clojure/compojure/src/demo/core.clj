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

  ; Inline regex constraint `:id{[0-9]+}` must normalize to `:id` in the URL,
  ; and the `:<<` coercion fn (`as-int`) must NOT become a query param.
  (GET "/orders/:id{[0-9]+}" [id :<< as-int]
    {:id id})

  (context "/api" []
    (POST "/users" request
      request)

    (context "/admin" []
      (DELETE "/users/:id" [id force]
        {:id id :force force}))

    (ANY "/ping" []
      "pong"))

  ; compojure.api.resource: method-keyed map bound to the context path —
  ; emits GET/POST /widgets, plus a path param from `/widgets/:id`.
  (context "/widgets" []
    (resource
      {:get {:summary "list widgets"
             :handler (fn [_] "all")}
       :post {:parameters {:body-params NewWidget}
              :handler (fn [_] "created")}}))

  (context "/widgets/:id" []
    (resource
      {:get {:handler (fn [_] "one")}}))

  ; A bare `:handler` resource (no method key) serves every method → GET.
  (context "/health-check" []
    (resource
      {:handler (fn [_] "ok")}))

  ; compojure-api restructuring directives declare typed params in the body.
  ; `{y :- Long 1}` is an optional param with a default → still bound as `y`.
  (GET "/calc" []
    :query-params [x :- Long, {y :- Long 1}]
    :return Long
    (ok (+ x y)))

  (POST "/echo" []
    :body-params [message :- s/Str]
    :header-params [authorization :- s/Str]
    (ok message))

  ; `:path-params` re-declaring the URL param must not duplicate it.
  (PUT "/upload/:id" []
    :path-params [id :- Long]
    :form-params [file :- s/Str]
    (ok id))

  (routes
    (GET "/health" []
      "ok")))
