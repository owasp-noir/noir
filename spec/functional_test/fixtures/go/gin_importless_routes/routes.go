package main

func registerRoutes(r RouteRegistrar) {
	r.GET("/features", getFeature)
	r.POST("/features", createFeature)
}
