package response

import "net/http"

func Unauthorized(w http.ResponseWriter, r *http.Request) {
	_ = r.Header.Get("Accept-Encoding")
	w.WriteHeader(http.StatusUnauthorized)
}
