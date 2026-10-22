package main

import "github.com/gin-gonic/gin"

func main() {
	r := gin.Default()

	// Registered before r.Use, so ForwardMid does not run for it.
	r.GET("/early", func(c *gin.Context) {
		c.JSON(200, gin.H{})
	})

	r.Use(ForwardMid)

	r.GET("/echo", func(c *gin.Context) {
		req := c.Request
		ip := req.Header.Get("X-Forwarded-For")
		vals := req.Header.Values("X-Multi")
		c.Request.Header["X-Written"] = []string{ip}
		_ = c.Writer.Header().Get("X-Response")
		c.JSON(200, gin.H{"ip": ip, "v": vals})
	})

	authorized := r.Group("/admin", gin.BasicAuth(gin.Accounts{"foo": "bar"}))
	authorized.POST("/users", func(c *gin.Context) {
		c.JSON(200, gin.H{})
	})

	r.GET("/after", func(c *gin.Context) {
		c.JSON(200, gin.H{})
	})

	_ = r.Run(":8080")
}

func ForwardMid(c *gin.Context) {
	if v, ok := c.Request.Header["Forward"]; ok && v[0] == "ok" {
		c.Abort()
		return
	}
	c.Next()
}

// A different `r` in another function: main's r.Use does not reach it.
func other() {
	r := gin.New()
	r.GET("/other", func(c *gin.Context) {
		c.JSON(200, gin.H{})
	})
}
