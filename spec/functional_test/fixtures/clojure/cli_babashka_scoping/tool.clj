(ns tool.core
  (:require [babashka.cli :as cli]))

(defn start-cmd [{:keys [opts]}]
  (println "starting docker container" (:detach opts)))

(defn stop-cmd [{:keys [opts]}]
  (println "stopping docker container" (:force opts)))

;; Map literals are unordered — this entry's :spec deliberately precedes its
;; :cmds sibling, and :cmds itself has two segments ("docker" "start").
(def table
  [{:spec {:detach {:coerce :boolean}
           :verbose {:desc "extra logging"}}
    :cmds ["docker" "start"]
    :fn start-cmd}
   {:cmds ["docker" "stop"]
    :spec {:force {:coerce :boolean}}
    :fn stop-cmd}])

;; Unrelated map shaped like a babashka.cli option entry, declared after the
;; last dispatch entry. It is NOT inside any :spec map, so it must never be
;; attributed to tool/docker/stop (or anywhere else).
(def log-opts
  {:level {:coerce :keyword}})

(defn -main [& args]
  (cli/dispatch table args))
