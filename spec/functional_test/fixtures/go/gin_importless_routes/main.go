package main

import "github.com/gin-gonic/gin"

type RouteRegistrar interface {
	GET(string, ...gin.HandlerFunc) gin.IRoutes
	POST(string, ...gin.HandlerFunc) gin.IRoutes
}

func main() {
	r := gin.Default()
	registerRoutes(r)
}

func getFeature(c *gin.Context) {}

func createFeature(c *gin.Context) {}
