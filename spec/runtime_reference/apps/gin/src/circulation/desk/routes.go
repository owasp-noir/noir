package desk

import "github.com/gin-gonic/gin"

type Desk struct {
	group *gin.RouterGroup
}

func Register(branch *gin.RouterGroup) {
	desk := Desk{group: branch.Group("/desk")}
	desk.registerLoans()
}

func (d Desk) registerLoans() {
	d.group.GET("/loans/:id", loan)
	d.group.Handle("PATCH", "/loans/:id", loan)
	for _, route := range []struct {
		method, path string
		handler      gin.HandlerFunc
	}{
		{"GET", "/holds", list},
		{"POST", "/holds", Accept},
		{"DELETE", "/holds/:id", cancel},
		{"GET", "/receipts", list},
		{"POST", "/returns", Accept},
	} {
		d.group.Handle(route.method, route.path, route.handler)
	}
}
