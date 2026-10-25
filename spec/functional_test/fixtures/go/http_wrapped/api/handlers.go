package api

import (
	"encoding/json"
	"net/http"

	"example.com/app/model"
	"example.com/app/request"
	"example.com/app/response"
)

func (h *handler) createItem(w http.ResponseWriter, r *http.Request) {
	var req model.ItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func (h *handler) getItem(w http.ResponseWriter, r *http.Request) {
	_ = request.RouteInt64Param(r, "itemID")
	_ = request.QueryFlag(r, "full")
	_ = request.HasFlag(r, "verbose")
	resp, _ := http.Get("http://upstream/items")
	_ = resp.Header.Get("Content-Type")
	response.Unauthorized(w, r)
	w.WriteHeader(http.StatusOK)
}
