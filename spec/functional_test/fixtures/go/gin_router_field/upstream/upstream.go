package upstream

import "github.com/gin-gonic/gin"

// A `router` field of a non-router type in another package: main's
// `router *gin.Engine` must not make these calls routes.
type Pool struct{}

func (p *Pool) Get(path string, h gin.HandlerFunc) {}

type Proxy struct {
	router *Pool
}

func (p *Proxy) Forward() {
	p.router.Get("/upstream", p.h)
}

func (p *Proxy) h(c *gin.Context) {}
