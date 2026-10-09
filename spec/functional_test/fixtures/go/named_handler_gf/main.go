package main

import (
	"github.com/gogf/gf/v2/frame/g"
	"github.com/gogf/gf/v2/net/ghttp"
)

func listC(r *ghttp.Request) {
	_ = r.GetQuery("qc")
}

func main() {
	s := g.Server()
	s.BindHandler("/a", listA)
	s.BindHandler("/b", listB)
	s.BindHandler("/c", listC)
	s.Run()
}

func listA(r *ghttp.Request) {
	_ = r.GetQuery("qa")
}

func listB(r *ghttp.Request) {
	_ = r.GetQuery("qb")
}
