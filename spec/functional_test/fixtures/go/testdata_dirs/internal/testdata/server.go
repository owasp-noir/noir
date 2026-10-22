package testdata

import "net/http"

func Register() {
	http.HandleFunc("GET /fake/nested", func(w http.ResponseWriter, r *http.Request) {})
}
