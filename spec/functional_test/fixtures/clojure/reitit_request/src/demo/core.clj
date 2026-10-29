(ns demo.core
  (:require [reitit.ring :as ring]))

(def app
  (ring/ring-handler
    (ring/router
      [["/minus"
        {:get {:parameters {:query (s/keys :req-un [::x ::y] :opt-un [::z])}
               :handler (fn [_] {:status 200})}}]
       ["/malli"
        {:get {:parameters {:query [:map [:x :int] [:y :int]]}
               :handler (fn [_] {:status 200})}}]
       ["/pizza"
        {:post {:request {:content {"application/json" {:schema [:map [:color :keyword] [:pineapple :boolean]]}}}
                :handler (fn [_] {:status 200})}}]])))
