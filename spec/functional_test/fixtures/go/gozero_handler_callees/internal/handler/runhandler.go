package handler

import (
	"net/http"

	"github.com/zeromicro/go-zero/rest/httpx"

	"example.com/gozerocallees/internal/logic"
)

func RunHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req logic.Req
		if err := httpx.Parse(r, &req); err != nil {
			return
		}
		l := logic.NewRunLogic(r.Context())
		l.Run(&req)
	}
}
