package handler

import (
	"net/http"

	"github.com/zeromicro/go-zero/rest/httpx"
)

func DetailHandler(svcCtx *ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		httpx.OkJsonCtx(r.Context(), w, nil)
	}
}

func UpdateHandler(svcCtx *ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		httpx.OkJsonCtx(r.Context(), w, nil)
	}
}
