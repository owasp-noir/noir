package router

import "github.com/gin-gonic/gin"

var shadowed []func(*gin.RouterGroup)

func init() { shadowed = append(shadowed, regShadowA) }

func regShadowA(g *gin.RouterGroup) { g.GET("/sa", showA) }
func regShadowB(g *gin.RouterGroup) { g.GET("/sb", showB) }
func regLocal(g *gin.RouterGroup)   { g.GET("/local", showLocal) }

func SetupShadow(r *gin.Engine) {
	v2 := r.Group("/v2")
	for _, f := range shadowed {
		f(v2)
	}
}

// A local slice of the package slice's name is another slice.
func SetupShadowAdmin(r *gin.Engine) {
	shadowed := []func(*gin.RouterGroup){regShadowB}
	adm := r.Group("/adm")
	for _, f := range shadowed {
		f(adm)
	}
}

// shadowed = append(shadowed, regShadowB)
func lookalike() string { return "shadowed = append(shadowed, regLocal)" }

// A function-local slice is not the package's registration list.
func setupLocal(r *gin.Engine) {
	var list []func(*gin.RouterGroup)
	list = append(list, regLocal)
	pub := r.Group("/pub")
	for _, f := range list {
		f(pub)
	}
}
