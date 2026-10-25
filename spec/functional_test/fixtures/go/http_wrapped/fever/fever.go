package fever

import "net/http"

type feverHandler struct{}

func NewHandler() http.Handler {
	h := &feverHandler{}
	return http.HandlerFunc(h.serve)
}

func (h *feverHandler) serve(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Query().Has("groups"):
		w.WriteHeader(http.StatusOK)
	case r.FormValue("mark") == "item":
		w.WriteHeader(http.StatusOK)
	}
}

func Middleware() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			apiKey := r.FormValue("api_key")
			if apiKey == "" {
				w.Write([]byte(`{"auth":0}`))
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
