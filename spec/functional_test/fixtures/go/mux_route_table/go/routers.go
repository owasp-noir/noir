package swagger

import (
	"net/http"
	"strings"

	"github.com/gorilla/mux"
)

type Route struct {
	Name        string
	Method      string
	Pattern     string
	HandlerFunc http.HandlerFunc
}

type Routes []Route

func NewRouter() *mux.Router {
	router := mux.NewRouter().StrictSlash(true)
	for _, route := range routes {
		var handler http.Handler
		handler = route.HandlerFunc
		handler = Logger(handler, route.Name)

		router.
			Methods(route.Method).
			Path(route.Pattern).
			Name(route.Name).
			Handler(handler)
	}

	return router
}

func Logger(inner http.Handler, name string) http.Handler { return inner }

var routes = Routes{
	Route{
		"Index",
		"GET",
		"/v2/",
		Index,
	},

	Route{
		"AddPet",
		strings.ToUpper("Post"),
		"/v2/pet",
		AddPet,
	},

	Route{
		"GetPetById",
		strings.ToUpper("Get"),
		"/v2/pet/{petId}",
		GetPetById,
	},
}

func Index(w http.ResponseWriter, r *http.Request)      {}
func AddPet(w http.ResponseWriter, r *http.Request)     {}
func GetPetById(w http.ResponseWriter, r *http.Request) { _ = mux.Vars(r)["petId"] }
