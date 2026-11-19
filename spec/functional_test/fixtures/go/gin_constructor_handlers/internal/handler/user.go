package handler

import "github.com/gin-gonic/gin"

type UserHandler struct{}

func NewUserHandler() *UserHandler { return &UserHandler{} }

type CreateUserReq struct {
	Email string `json:"email"`
	Role  string `json:"role"`
}

func (h *UserHandler) List(c *gin.Context) {
	_ = c.Query("user_page")
}

func (h *UserHandler) Create(c *gin.Context) {
	var req CreateUserReq
	_ = c.ShouldBindJSON(&req)
}
