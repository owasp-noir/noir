package handler

import "github.com/gin-gonic/gin"

type QuestionHandler struct{}

func (h *QuestionHandler) Info(c *gin.Context) {
	_ = c.Param("id")
	_ = c.Param("answerid")
	_ = c.Query("share")
}
