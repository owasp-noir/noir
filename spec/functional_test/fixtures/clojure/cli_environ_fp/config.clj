(ns myapp.config
  (:require [environ.core :refer [env]]))

(def db-url (env :database-url))
(def api-key (env :api-key))
