package fileserver

import (
	"net/http"

	"example.com/app/internal/httphandler"
)

type Service struct{}

// RegisterRoutes registers on the mux the server hands in.
func (s *Service) RegisterRoutes(mux *http.ServeMux, fallback http.Handler) {
	mux.Handle("/file/attachments/{uid}", httphandler.GET(httphandler.Func(s.serveAttachment), fallback))
	mux.Handle("GET "+exportRoute, httphandler.Func(s.serveExport))
}

func (s *Service) serveAttachment(w http.ResponseWriter, r *http.Request) error { return nil }
func (s *Service) serveExport(w http.ResponseWriter, r *http.Request) error     { return nil }
