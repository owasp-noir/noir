package handler

import "github.com/gin-gonic/gin"

type OrderHandler struct{}

func NewOrderHandler() (*OrderHandler, error) { return &OrderHandler{}, nil }

func (h *OrderHandler) List(c *gin.Context) {
	_ = c.Query("order_status")
}
