package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	r := gin.Default()

	// Public routes
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	r.GET("/public", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"message": "public"})
	})

	// Auth middleware protected group
	api := r.Group("/api")
	api.Use(AuthMiddleware())
	api.GET("/profile", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"user": "profile"})
	})

	// Inline auth middleware
	r.GET("/dashboard", AuthRequired, func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"dashboard": true})
	})

	// Admin route with role check
	r.DELETE("/admin/users/:id", AdminOnly, func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"deleted": true})
	})

	// Middleware handed to the group constructor, with a name the lists do
	// not know: its body answers 401, which is what makes it a guard. The
	// group adds no path segment, so the parent's own route shares its
	// prefix and must stay public.
	v1 := r.Group("/v1")
	v1.GET("/users", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"users": []string{}})
	})
	authV1 := v1.Group("/", Checkpoint())
	authV1.POST("/users/add", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"added": true})
	})

	// Per-route middleware with an unknown name whose body answers 403.
	r.GET("/home", CookieTool(), func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"data": "home"})
	})

	// A middleware that only logs and passes the request on is not a guard.
	traced := r.Group("/traced", Trace())
	traced.GET("/ping", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"pong": true})
	})
	r.GET("/metrics", Trace(), func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"requests": 0})
	})

	// Named like guards, but their bodies only pass the request on.
	refreshed := r.Group("/", TokenRefresher())
	refreshed.GET("/session", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"session": true})
	})
	logged := r.Group("/logged")
	logged.Use(LoginLogger())
	logged.GET("/events", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"events": []string{}})
	})

	r.Run(":8080")
}

func TokenRefresher() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()
	}
}

func LoginLogger() gin.HandlerFunc {
	return func(c *gin.Context) {
		println("login", c.Request.URL.Path)
		c.Next()
	}
}

func Checkpoint() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.PostForm("user") == "foo" && c.PostForm("password") == "bar" {
			return
		}
		c.AbortWithStatus(http.StatusUnauthorized)
	}
}

func CookieTool() gin.HandlerFunc {
	return func(c *gin.Context) {
		if cookie, err := c.Cookie("label"); err == nil && cookie == "ok" {
			c.Next()
			return
		}
		c.JSON(http.StatusForbidden, gin.H{"error": "Forbidden with no cookie"})
		c.Abort()
	}
}

func Trace() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Status 401 responses are logged here, never produced: a comparison
		// is not a rejection.
		c.Next()
		if c.Writer.Status() == http.StatusUnauthorized {
			println("unauthorized", c.Request.URL.Path)
		}
	}
}

// AuthMiddleware validates JWT tokens from the Authorization header.
// Simplified for fixture purposes — production code should verify token signature.
func AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := c.GetHeader("Authorization")
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}
		// TODO: validate token signature in production
		c.Next()
	}
}

func AuthRequired(c *gin.Context) {
	token := c.GetHeader("Authorization")
	if token == "" {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	c.Next()
}

func AdminOnly(c *gin.Context) {
	role := c.GetString("role")
	if role != "admin" {
		c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "forbidden"})
		return
	}
	c.Next()
}
