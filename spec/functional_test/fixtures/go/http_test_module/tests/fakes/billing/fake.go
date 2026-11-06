package billing

import "net/http"

// Stands in for the billing provider during integration tests.
func Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/charges", charge)
	return mux
}

func charge(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusCreated)
}
