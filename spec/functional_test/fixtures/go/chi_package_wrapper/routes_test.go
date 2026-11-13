package main

import "testing"

func TestRoutes(t *testing.T) {
	r := newRouter()
	r.Get("/test-only", health)
}
