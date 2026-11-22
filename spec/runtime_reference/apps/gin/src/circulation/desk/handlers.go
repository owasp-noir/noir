package desk

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func loan(c *gin.Context)   { c.JSON(http.StatusOK, gin.H{"id": c.Param("id")}) }
func list(c *gin.Context)   { c.JSON(http.StatusOK, []string{}) }
func cancel(c *gin.Context) { c.Status(http.StatusNoContent) }
func Accept(c *gin.Context) { c.Status(http.StatusAccepted) }
func Status(c *gin.Context) { c.String(http.StatusOK, "ready") }
