package handler

import (
	"net/http"
	"os"
	"path/filepath"

	"github.com/gin-gonic/gin"
)

type UserHandler struct{}

func NewUserHandler() *UserHandler { return &UserHandler{} }

func (h *UserHandler) RegisterRoutes(rg *gin.RouterGroup) {
	rg.GET("/:id/avatar", h.Avatar)
	rg.DELETE("/:id", h.Delete)
}

func (h *UserHandler) Avatar(c *gin.Context) {
	data, err := os.ReadFile(filepath.Join("/var/avatars", c.Param("id")))
	if err != nil {
		c.Status(http.StatusNotFound)
		return
	}
	c.Data(http.StatusOK, "image/png", data)
}

func (h *UserHandler) Delete(c *gin.Context) {
	os.Remove(filepath.Join("/var/avatars", c.Param("id")))
	c.Status(http.StatusNoContent)
}
