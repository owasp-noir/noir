package main

func setup() {
	r = r.Group("/v1")
	r.Get("/x", h)
}
