package main

func registerRoutes(e RouteRegistrar) {
	e.GET("/features", getFeature)
	e.POST("/features", createFeature)
}
