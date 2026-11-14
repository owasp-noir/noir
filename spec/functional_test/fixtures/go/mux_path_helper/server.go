package main

import (
	"net/http"
	"strings"

	"github.com/gorilla/mux"
)

type Config struct {
	Prefix string
}

type Server struct {
	router *mux.Router
	config Config
}

// prefixedPath mounts every route under the configured prefix.
func (s *Server) prefixedPath(route string) string {
	prefix := s.config.Prefix
	if prefix == "" || prefix == "/" {
		return route
	}
	if strings.HasPrefix(route, "/") {
		return prefix + route
	}
	return prefix + "/" + route
}

// apiPath is a fully static wrapper.
func apiPath(r string) string {
	return "/api" + r
}

// lookupPath returns nothing the scan can read: its routes are dropped.
func lookupPath(name string) string {
	return routeTable[name]
}

var routeTable = map[string]string{}

func (s *Server) version(w http.ResponseWriter, r *http.Request) {}
func (s *Server) store(w http.ResponseWriter, r *http.Request)   {}
func (s *Server) read(w http.ResponseWriter, r *http.Request)    {}
func (s *Server) health(w http.ResponseWriter, r *http.Request)  {}
func (s *Server) hidden(w http.ResponseWriter, r *http.Request)  {}

func (s *Server) registerHandlers() {
	s.router.HandleFunc(s.prefixedPath("/version"), s.version).Methods("GET")
	s.router.HandleFunc(s.prefixedPath("/store"), s.store).Methods("POST")
	s.router.HandleFunc(s.prefixedPath("/store/{hash}"), s.read).Methods("GET")
	s.router.Path(apiPath("/health")).Methods("GET").HandlerFunc(s.health)
	s.router.HandleFunc(lookupPath("hidden"), s.hidden).Methods("GET")
}

func (s *Server) ping() {
	// An HTTP client call through the same wrapper is not a route.
	http.Get(apiPath("/remote"))
}

func main() {
	s := &Server{router: mux.NewRouter()}
	s.registerHandlers()
	http.ListenAndServe(":8080", s.router)
}
