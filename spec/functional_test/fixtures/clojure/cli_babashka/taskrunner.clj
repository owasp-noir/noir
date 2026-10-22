(ns taskrunner.core
  (:require [babashka.cli :as cli]))

(defn run-cmd [{:keys [opts]}]
  (println "starting on port" (:port opts)))

(defn build-cmd [{:keys [opts]}]
  (println "building" (:tag opts)))

(def table
  [{:cmds ["run"]
    :fn run-cmd
    :spec {:port {:coerce :long}
           :verbose {:coerce :boolean}}}
   {:cmds ["build"]
    :fn build-cmd
    :spec {:tag {:coerce :string}}}])

(defn -main [& args]
  (cli/dispatch table args))
