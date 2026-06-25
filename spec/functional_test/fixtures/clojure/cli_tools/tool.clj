(ns tool.core
  (:require [clojure.tools.cli :refer [parse-opts]]))

(def cli-options
  [["-p" "--port PORT" "Port number"]
   ["-v" "--verbose"]])

(defn -main [& args]
  (let [{:keys [options]} (parse-opts args cli-options)
        token (System/getenv "API_TOKEN")]
    [options token]))
