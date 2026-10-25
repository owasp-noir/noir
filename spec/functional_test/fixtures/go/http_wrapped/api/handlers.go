package api

import (
	"encoding/json"
	"net/http"

	"example.com/app/model"
	"example.com/app/request"
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
	w.WriteHeader(http.StatusOK)
}
