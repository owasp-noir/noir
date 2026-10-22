package main

import (
	"github.com/gin-gonic/gin"

	"example.com/app/handlers"
)

type Users struct{}
type Posts struct{}

func main() {
	r := gin.Default()
	u, p := &Users{}, &Posts{}
	// Two controllers share the method name `List`: each selector resolves
	// by its receiver's type, so `/users` must never pick up `post_q`.
	r.GET("/users", u.List)
	r.GET("/posts", p.List)
	// `handlers.Show` lives in another package; the local `Show` method
	// below is unrelated and is not credited to `/show`.
	r.GET("/show", handlers.Show)
	r.GET("/last", func(c *gin.Context) {})
}

func (u *Users) List(c *gin.Context) {
	_ = c.Query("user_q")
}

func (p *Posts) List(c *gin.Context) {
	_ = c.Query("post_q")
}

type local struct{}

func (l *local) Show(c *gin.Context) {
	_ = c.Query("local_q")
}
