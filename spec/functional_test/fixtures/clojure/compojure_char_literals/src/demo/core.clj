(ns demo.core
  (:require [compojure.core :refer [defroutes GET POST]]
            [ring.util.response :as response]))

;; Character literals sitting above the routes. `\(` is not an open paren,
;; `\"` does not open a string, `\;` does not start a comment and `\\` is the
;; backslash character itself rather than an escape — get any of them wrong
;; and the reader loses track of depth, taking every route below with it.
(defn render-row [row]
  (let [open \( close \) quote-char \" semi \; back \\ nl \newline]
    (formatter/render row open close quote-char semi back nl)))

(defroutes app-routes
  (GET "/rows" []
    (response/ok (render-row (row.service/list))))

  (POST "/rows" request
    (let [sep \tab code \u00e9 oct \o101]
      (response/created "/rows/1" (row.service/create! request sep code oct)))))
