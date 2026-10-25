package reader

import "net/http"

type readerHandler struct{}

func NewHandler() http.Handler {
	h := &readerHandler{}
	auth := newAuthMiddleware()
	withKey := func(fn http.HandlerFunc) http.Handler {
		return auth.validate(fn)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /reader/login", h.login)
	mux.Handle("POST /reader/edit", withKey(h.edit))
	return mux
}

func (h *readerHandler) login(w http.ResponseWriter, r *http.Request) {
	_ = r.Form.Get("Email")
}

func (h *readerHandler) edit(w http.ResponseWriter, r *http.Request) {
	_ = r.PostForm.Get("a")
}

type authMiddleware struct{}

func newAuthMiddleware() *authMiddleware {
	return &authMiddleware{}
}

func (m *authMiddleware) validate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		m.serve(w, r, next)
	})
}

func (m *authMiddleware) serve(w http.ResponseWriter, r *http.Request, next http.Handler) {
	if r.Header.Get("Authorization") == "" {
		sendUnauthorized(w)
		return
	}
	next.ServeHTTP(w, r)
}

func sendUnauthorized(w http.ResponseWriter) {
	w.WriteHeader(http.StatusUnauthorized)
}
