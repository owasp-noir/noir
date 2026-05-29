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
                     (response/ok (inline.service/run request)))}}]])

(def app
  (ring/ring-handler
    (ring/router routes)))
