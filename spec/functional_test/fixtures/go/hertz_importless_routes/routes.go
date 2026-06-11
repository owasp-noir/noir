package main

func registerRoutes(r RouteRegistrar) {
	r.GET("/features", getFeature)
	r.POST("/features", createFeature)
	r.Handle("PATCH", "/features/:id", updateFeature)
	r.Handle("LOAD", "/custom-method", customMethodFeature)
}
