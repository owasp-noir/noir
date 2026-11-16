package handler

import (
	"net/http"

	"example.com/app/internal/service"
	"github.com/gin-gonic/gin"
)

type UserHandler struct {
	svc    *service.UserService
	runner service.Runner
}

func NewUserHandler(svc *service.UserService, runner service.Runner) *UserHandler {
	return &UserHandler{svc: svc, runner: runner}
}

func (h *UserHandler) Export(c *gin.Context) {
	c.JSON(http.StatusOK, h.svc.RunExport(c.PostForm("target")))
}

func (h *UserHandler) Search(c *gin.Context) {
	users, err := h.svc.Search(c.Query("name"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, users)
}

func (h *UserHandler) Ambiguous(c *gin.Context) {
	c.JSON(http.StatusOK, h.runner.Run(c.Query("q")))
}

func (h *UserHandler) Cycle(c *gin.Context) {
	c.JSON(http.StatusOK, h.svc.PingA(3))
}

func (h *UserHandler) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": h.svc.Status()})
}
