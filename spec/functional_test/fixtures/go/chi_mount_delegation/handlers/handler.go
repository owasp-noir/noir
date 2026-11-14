package handlers

import (
	"net/http"

	"example.com/shop/handlers/generated"
)

type ServerInterfaceImpl struct{}

func New() *ServerInterfaceImpl {
	return &ServerInterfaceImpl{}
}

func (s *ServerInterfaceImpl) Handler() http.Handler {
	return generated.Handler(s)
}

func (s *ServerInterfaceImpl) GetEmoji(w http.ResponseWriter, r *http.Request) {}
func (s *ServerInterfaceImpl) GetChat(w http.ResponseWriter, r *http.Request)  {}
