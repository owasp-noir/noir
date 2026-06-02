(ns demo.core
  (:require [compojure.core :refer [defroutes GET POST DELETE context]]
            [ring.util.response :as response]))

(defroutes app-routes
  (GET "/users/:id" [id]
    (let [user (user.service/find-user id)]
      (audit.log/write! "show" user)
      (response/ok (present-user user))))

  (POST "/users" request
    (let [payload (payload/from-request request)
          user (user.service/create! payload)]
      (response/created (str "/users/" (:id user)) (present-user user))))

  (context "/api" []
    (DELETE "/users/:id" [id force]
      (audit.log/write! "delete" id)
      (response/ok (user.service/delete! id force))))

  (GET "/quoted" []
    ; (ignored/comment)
    "(ignored/string)"
    '(ignored/quoted)
    (quote (ignored/again))
    (response/ok (safe.service/run!)))

  ; Var-quoted handler `#'sym` (the idiomatic hot-reload form) must be
  ; captured as a callee, unlike an ordinary `'quote`.
  (GET "/vars" []
    (wrap #'handlers/show-vars))

  ; Arithmetic / comparison operators are not meaningful callees: only the
  ; real service call should surface.
  (GET "/calc" []
    (response/ok (/ (+ 1 2) (math.util/scale 3))))

  ; compojure.api.resource — handlers under each method key become callees.
  (context "/items" []
    (resource
      {:get {:handler (fn [_] (item.service/list-all))}
       :post {:handler (fn [req] (item.service/create! req))}})))
