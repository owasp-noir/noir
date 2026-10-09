(ns demo.core)

(defn handler [req]
  (cond
    (= "/ring/live" (:uri req)) {:status 200}
    #_(= "/ring/off" (:uri req)) #_{:status 200}
    :else {:status 404}))

(comment
  (= "/ring/in-comment" (:uri req)))
