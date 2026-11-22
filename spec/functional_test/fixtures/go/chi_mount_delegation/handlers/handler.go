package handlers

import (
	"net/http"
	"encoding/json"

	"example.com/shop/handlers/generated"
)

type ServerInterfaceImpl struct { messages mailbox }

func New() *ServerInterfaceImpl {
	return &ServerInterfaceImpl{}
}

func (s *ServerInterfaceImpl) Handler() http.Handler {
	return generated.Handler(s)
}

func (s *ServerInterfaceImpl) GetEmoji(w http.ResponseWriter, r *http.Request) {}
func (s *ServerInterfaceImpl) GetChat(w http.ResponseWriter, r *http.Request) {
	apply(s.messages.read, s.messages.ignore)(w, r)
}

type mailbox struct{}

func (mailbox) read(w http.ResponseWriter, r *http.Request) {
	var input struct { Cursor string `json:"cursor"` }
	json.NewDecoder(r.Body).Decode(&input)
}

func (mailbox) ignore(w http.ResponseWriter, r *http.Request) { r.FormValue("unused") }

func apply(selected, unused http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) { selected(w, r) }
}
