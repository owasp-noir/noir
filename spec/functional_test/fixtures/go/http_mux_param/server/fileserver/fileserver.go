package fileserver

import (
	"net/http"

	"example.com/app/internal/hh"
)

type Service struct{}

// RegisterRoutes registers on the mux the server hands in.
func (s *Service) RegisterRoutes(mux *http.ServeMux, fallback http.Handler) {
	mux.Handle("/file/attachments/{uid}", hh.GET(hh.Func(s.serveAttachment), fallback))
	mux.Handle("GET "+exportRoute, hh.Func(s.serveExport))
}

func (s *Service) serveAttachment(w http.ResponseWriter, r *http.Request) error { return nil }
func (s *Service) serveExport(w http.ResponseWriter, r *http.Request) error     { return nil }
