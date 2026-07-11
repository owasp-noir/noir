(ns myapp.toolkit
  (:require [clojure.tools.cli :refer [parse-opts]]
            [environ.core :as environ]))

(def cli-options
  [["-t" "--timeout SECONDS" "Timeout in seconds"]])

;; `env` here is just a local fn param (a very common Clojure idiom for "the
;; current config map") — nothing to do with environ.core, which was only
;; ever required under the `environ` alias below.
(defn ->config [env]
  (env :timeout))

(defn db-url []
  (environ/env :database-url))

(defn -main [& args]
  (let [{:keys [options]} (parse-opts args cli-options)]
    (->config options)))
