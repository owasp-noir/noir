package main

import (
	"net/http"

	"github.com/julienschmidt/httprouter"
)

type application struct{}

func (app *application) routes() http.Handler {
	router := httprouter.New()

	router.NotFound = http.HandlerFunc(app.notFoundResponse)

	router.HandlerFunc(http.MethodGet, "/v1/healthcheck", app.healthcheckHandler)
	router.HandlerFunc(http.MethodGet, "/v1/movies", app.listMoviesHandler)
	router.HandlerFunc(http.MethodGet, "/v1/movies/:id", app.showMovieHandler)
	router.HandlerFunc("DELETE", "/v1/movies/:id", app.healthcheckHandler)
	router.Handler(http.MethodGet, "/debug/vars", http.DefaultServeMux)
	router.GET("/v1/native/:id", app.nativeHandler)

	return router
}

func (app *application) notFoundResponse(w http.ResponseWriter, r *http.Request)   {}
func (app *application) healthcheckHandler(w http.ResponseWriter, r *http.Request) {}

func (app *application) listMoviesHandler(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("title")
}

func (app *application) showMovieHandler(w http.ResponseWriter, r *http.Request) {
	params := httprouter.ParamsFromContext(r.Context())
	_ = params.ByName("id")
}

func (app *application) nativeHandler(w http.ResponseWriter, r *http.Request, ps httprouter.Params) {
	_ = ps.ByName("id")
}
