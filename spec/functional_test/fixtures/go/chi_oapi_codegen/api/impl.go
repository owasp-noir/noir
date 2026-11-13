package api

import "net/http"

type Impl struct{}

func (Impl) GetStatus(w http.ResponseWriter, r *http.Request)              {}
func (Impl) ListItems(w http.ResponseWriter, r *http.Request)              {}
func (Impl) CreateItem(w http.ResponseWriter, r *http.Request)             {}
func (Impl) GetItem(w http.ResponseWriter, r *http.Request, itemId string) {}
