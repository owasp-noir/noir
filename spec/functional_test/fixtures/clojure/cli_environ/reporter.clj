(ns reporter.core
  (:require [clojure.tools.cli :refer [parse-opts]]
            [environ.core :refer [env]]))

(def cli-options
  [["-v" "--verbose" "Verbose output"]])

(defn -main [& args]
  (let [{:keys [options]} (parse-opts args cli-options)
        db-url  (env :database-url)
        api-key (env :api-key)]
    (println "connecting to" db-url "with" api-key "verbose?" (:verbose options))))
