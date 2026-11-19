package main

import (
	"example.com/ginctor/internal/handler"
	"github.com/gin-gonic/gin"
)

type Handlers struct {
	User *handler.UserHandler
}

type Server struct {
	engine   *gin.Engine
	handlers *Handlers
	orders   *handler.OrderHandler
}
