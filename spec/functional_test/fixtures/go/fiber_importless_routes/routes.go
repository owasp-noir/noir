package main

func registerRoutes(r RouteRegistrar) {
	r.Get("/features", getFeature)
	r.Post("/features", createFeature)
}
