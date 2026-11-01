package httphandler

import "net/http"

type Func func(w http.ResponseWriter, r *http.Request) error

func (f Func) ServeHTTP(w http.ResponseWriter, r *http.Request) { _ = f(w, r) }

// GET serves handler for GET requests and hands every other method to fallback.
func GET(handler, fallback http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			fallback.ServeHTTP(w, r)
			return
		}
		handler.ServeHTTP(w, r)
	})
}
