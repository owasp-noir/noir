package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/spf13/viper"

	"example.com/ginaccessor/client"
	"example.com/ginaccessor/config"
	"example.com/ginaccessor/legacy"
	"example.com/ginaccessor/router"
	"example.com/ginaccessor/store"
)

func init() {
	router.V1().POST("/login", login)
	router.V1().GET("/me", me)
	router.Router().GET("/healthz", health)
	router.V1().Group("/users").GET("/:id", me)
}

type Service struct {
	client *http.Client
	cache  interface{ Get(key string, h func()) string }
}

// None of these are routes: no accessor here returns a gin router.
func (s *Service) lookups(c *gin.Context, r *http.Request) {
	c.Request.Get("/not-a-route", s.h)
	r.Header.Get("/not-a-route-header")
	s.client.Get("/not-a-route-client")
	s.cache.Get("/not-a-route-cache", s.h)
	viper.Get("/not-a-route-viper")
	config.Get().Get("/not-a-route-config", s.h)
	store.Get().Delete("/not-a-route-store", s.h)
	client.New().Get("/not-a-route-http-client", s.h)
	legacy.V1().GET("/not-a-route-legacy", s.h)
}

func (s *Service) h() {}

func login(c *gin.Context) {
	_ = c.PostForm("username")
}

func me(c *gin.Context) {
	_ = c.Query("fields")
}

func health(c *gin.Context) {}
