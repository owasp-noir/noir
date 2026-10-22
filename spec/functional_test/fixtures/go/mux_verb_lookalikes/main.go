// gorilla/mux registers no routes through verb-named methods: `Router.Get`
// looks a named route up. `.Get("X", …)` / `.Any("k", v)` on env readers,
// caches and structured loggers used to be read as routes — MinIO's
// `env.Get("_MINIO_SCANNER", …)` came out as `GET /_MINIO_SCANNER`.
package main

import (
	"net/http"

	"github.com/gorilla/mux"
)

func main() {
	if env.Get("_APP_SCANNER", config.EnableOn) == config.EnableOn {
		defer func() {
			if r := recover(); r != nil {
				log.Error("recovered", log.Any("panic", r))
			}
		}()
	}

	router := mux.NewRouter()
	router.HandleFunc("/users", listUsers).Methods(http.MethodGet).Name("users")
	router.Methods(http.MethodPost).Path("/users").HandlerFunc(createUser)

	if route := router.Get("users"); route != nil {
		_ = route
	}

	http.ListenAndServe(":8080", router)
}

func listUsers(w http.ResponseWriter, r *http.Request) {
	var cached string
	cache.Get("latest_version_cache", &cached)
}

func createUser(w http.ResponseWriter, r *http.Request) {}
