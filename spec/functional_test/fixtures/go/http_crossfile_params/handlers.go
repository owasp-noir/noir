package main

import (
	"encoding/json"
	"net/http"
)

type handler struct{}

func (h *handler) index(w http.ResponseWriter, r *http.Request) {
	_ = r.URL.Query().Get("next")
	w.WriteHeader(http.StatusOK)
}

func (h *handler) getEntries(w http.ResponseWriter, r *http.Request) {
	h.findEntries(w, r)
}

func (h *handler) findEntries(w http.ResponseWriter, r *http.Request) {
	_ = request.QueryStringParamList(r, "status")
	_ = r.URL.Query().Get("starred")
	_ = r.PathValue("entryID")
	configureFilters(r)
	w.WriteHeader(http.StatusOK)
}

func (h *handler) createEntry(w http.ResponseWriter, r *http.Request) {
	var payload map[string]any
	_ = json.NewDecoder(r.Body).Decode(&payload)
	_ = r.Header.Get("X-Trace-ID")
	_ = r.FormValue("title")
	w.WriteHeader(http.StatusCreated)
}

func configureFilters(r *http.Request) {
	_ = request.HasQueryParam(r, "before")
}

var request requestHelpers

type requestHelpers struct{}

func (requestHelpers) QueryStringParamList(_ *http.Request, _ string) []string {
	return nil
}

func (requestHelpers) HasQueryParam(_ *http.Request, _ string) bool {
	return false
}
