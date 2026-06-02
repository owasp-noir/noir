package app

import (
	"net/http"

	"github.com/go-chi/chi/v5"
)

type Server struct {
	router chi.Router
}

func (s *Server) routes() {
	s.router = chi.NewRouter()

	// Selector-expression receiver (`s.router`) + constant path +
	// method-value handler.
	s.router.Get(healthzPath, s.health)

	s.router.Group(func(router chi.Router) {
		// Bare identifier receiver + constant path + method-value handler.
		router.Get(tokenPath, s.issueToken)
		// Concatenation of a path constant and a literal suffix.
		router.Post(adminPath+"/{username}/reset-password", s.resetPassword)
	})
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeOK(w)
}

func (s *Server) issueToken(w http.ResponseWriter, r *http.Request) {
	token := newToken()
	w.Write([]byte(token))
}

func (s *Server) resetPassword(w http.ResponseWriter, r *http.Request) {
}

func writeOK(w http.ResponseWriter) {
	w.Write([]byte("ok"))
}

func newToken() string {
	return "t"
}
