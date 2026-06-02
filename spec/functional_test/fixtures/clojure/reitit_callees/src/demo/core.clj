(ns demo.core
  (:require [reitit.ring :as ring]
            [ring.util.response :as response]))

(defn ^:private list-users [request]
  (let [users (user.service/list (:params request))]
    (audit.log/write! "list" users)
    (response/ok (present-users users))))

(defn create-user [request]
  (let [payload (payload/from-request request)]
    (response/created "/users/1" (user.service/create! payload))))

(def routes
  ["/api"
   ["/users"
    {:get {:handler #'list-users}
     :post {:handler `create-user}}]
   ["/inline"
    {:get {:handler (fn [request]
                     (response/ok (inline.service/run request)))}}]

   ; Method map carries no handler — the route-data `:handler` is what reitit
   ; dispatches to, so it must surface as the GET endpoint's callee.
   ["/items/:id"
    {:get {:parameters {:path {:id int?}}}
     :handler get-item}]

   ; Bare `:handler` (no method) — emit a GET endpoint with its callee.
   ["/health"
    {:handler health-check}]])

(def app
  (ring/ring-handler
    (ring/router routes)))
