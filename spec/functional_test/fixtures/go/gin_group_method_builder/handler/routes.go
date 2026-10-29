package handler

import "github.com/gin-gonic/gin"

type Handler struct{}

func NewHandler() *Handler { return &Handler{} }

func (h *Handler) ok(c *gin.Context) {}

// A router builder declared as a method, called as `h.Register(v1)`.
func (h *Handler) Register(v1 *gin.RouterGroup) {
	users := v1.Group("/users")
	users.POST("/login", h.ok)
	v1.GET("/tags", h.ok)
}
