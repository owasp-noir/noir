package main

func registerRoutes(r RouteRegistrar) {
	r.HandleFunc("/features", getFeature).Methods("GET", "POST")
	r.HandleFunc("/features/{id}", updateFeature).Methods("PATCH")
}
