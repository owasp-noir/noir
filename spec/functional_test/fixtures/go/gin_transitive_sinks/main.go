package main

import (
	"database/sql"

	"example.com/app/internal/handler"
	"example.com/app/internal/repo"
	"example.com/app/internal/service"
	"github.com/gin-gonic/gin"
)

func main() {
	db, _ := sql.Open("postgres", "")
	h := handler.NewUserHandler(service.NewUserService(repo.NewUserRepo(db)), &service.RunnerA{})
	r := gin.Default()
	r.POST("/export", h.Export)
	r.GET("/users/search", h.Search)
	r.GET("/ambiguous", h.Ambiguous)
	r.GET("/cycle", h.Cycle)
	r.GET("/health", h.Health)
	r.Run()
}
