package main

import g "github.com/gin-gonic/gin"

// `s.api` is grouped in server.go.
func (s *Server) other() {
	s.api.PUT("/w", s.h)
}

func (s *Server) ping(c *g.Context) {}
