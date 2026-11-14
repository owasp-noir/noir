package router

import "github.com/gin-gonic/gin"

var (
	router *gin.Engine
	v1     *gin.RouterGroup
	admin  *gin.RouterGroup
)

func init() {
	router = gin.New()
	v1 = router.Group("/api/v1")
	admin = router.Group("/admin")
}

func V1() *gin.RouterGroup { return v1 }

func Router() *gin.Engine { return router }

type Server struct{}

func (s *Server) Admin() *gin.RouterGroup { return admin }
