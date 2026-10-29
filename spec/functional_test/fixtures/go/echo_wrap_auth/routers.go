package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/go-chi/chi/v5"
)

func ginRoutes() {
	r := gin.Default()
	r.GET("/gin/me", ginAuth(ginMe))
	r.GET("/gin/open", ginMe)
}

func chiRoutes() {
	r := chi.NewRouter()
	r.Get("/chi/me", requireSession(chiMe))
	r.Get("/chi/raw", http.HandlerFunc(chiMe))
}

func ginAuth(next gin.HandlerFunc) gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.GetHeader("Authorization") == "" {
			c.AbortWithStatus(http.StatusUnauthorized)
			return
		}
		next(c)
	}
}

func requireSession(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if _, err := r.Cookie("session"); err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

func ginMe(c *gin.Context) {}

func chiMe(w http.ResponseWriter, r *http.Request) {}
