package catalog

import "github.com/gin-gonic/gin"

func Reply(c *gin.Context) { c.String(200, "books") }

func Mark(c *gin.Context) {
	c.Header("X-Catalog", "books")
	c.Next()
}

func Register(group *gin.RouterGroup) {
	group.Use(Mark)
	group.GET("/books", Reply)
	group.POST("/books", Mark, Reply)
	group.GET("/books/:id", Reply)
	group.PATCH("/books/:id", Reply)
	group.GET("/files/*parts", Reply)
	// Gin expresses an optional segment with two registrations.
	group.GET("/editions", Reply)
	group.GET("/editions/:year", Reply)
}

// Draft is a registrar just like Register, but is never called.
func Draft(group *gin.RouterGroup) {
	group.GET("/unpublished", Reply)
}
