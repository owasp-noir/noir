package main

import (
	"net/http"

	"github.com/gorilla/mux"
)

func h(w http.ResponseWriter, r *http.Request) {}

type Routes struct {
	APIRoot *mux.Router
	Users   *mux.Router
}

type API struct{ BaseRoutes *Routes }

func Init(root *mux.Router) *API {
	api := &API{BaseRoutes: &Routes{}}
	api.BaseRoutes.APIRoot = root.PathPrefix("/api/v4").Subrouter()
	api.BaseRoutes.Users = api.BaseRoutes.APIRoot.PathPrefix("/users").Subrouter()
	api.InitUser()
	return api
}

type S struct{ R *mux.Router }

func InitParam(users *mux.Router) {
	users.HandleFunc("/x", h).Methods(http.MethodGet)
}

func main() {
	r := mux.NewRouter()
	Init(r)
	local := r.PathPrefix("/local").Subrouter()
	local.HandleFunc("/ping", h).Methods(http.MethodGet)

	s := S{R: mux.NewRouter()}
	s.R.HandleFunc("/field", h).Methods(http.MethodGet)

	InitParam(r.PathPrefix("/api/param").Subrouter())

	r.HandleFunc("/plugins/{plugin_id:[A-Za-z0-9\\_\\-\\.]+}", h).Methods(http.MethodGet)
	r.HandleFunc(`/raw/{id:[a-z\-\.]+}`, h).Methods(http.MethodGet)
	r.HandleFunc("/\xc3\xa9t\xc3\xa9", h).Methods(http.MethodGet)
	http.ListenAndServe(":8080", r)
}
