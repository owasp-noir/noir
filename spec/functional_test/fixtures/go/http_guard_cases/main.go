package main

import (
	"errors"
	"net/http"
	"os"
	"strings"

	"example.com/cases/client"
	"example.com/cases/resp"
)

// Not middleware: a route registrar, an error writer called inside a
// handler, and a login handler factory all reply 401, but none wraps a
// handler.
func registerAccount(mux *http.ServeMux) {
	mux.HandleFunc("POST /account/login", func(w http.ResponseWriter, r *http.Request) {
		if r.FormValue("password") != "pw" {
			http.Error(w, "bad password", http.StatusUnauthorized)
			return
		}
	})
}

var errAuth = errors.New("auth")

func writeError(w http.ResponseWriter, err error) {
	if errors.Is(err, errAuth) {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	w.WriteHeader(http.StatusInternalServerError)
}

func handleLogin(users map[string]string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if users[r.FormValue("username")] != r.FormValue("password") {
			http.Error(w, "invalid credentials", http.StatusUnauthorized)
			return
		}
	}
}

// Middleware that let an anonymous caller through.
func optionalAuth(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") == "" {
			h.ServeHTTP(w, r)
			return
		}
		h.ServeHTTP(w, r)
	})
}

func idempotent(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		key := r.Header.Get("Idempotency-Key")
		if key == "" {
			http.Error(w, "missing Idempotency-Key", http.StatusBadRequest)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func paginate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cursor := r.URL.Query().Get("page_token")
		if cursor == "" {
			w.Write([]byte("[]"))
			return
		}
		next.ServeHTTP(w, r)
	})
}

func logPass(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("X-Api-Token")
		if token == "" {
			next.ServeHTTP(w, r)

			return
		}
		if token != "s" {
			resp.Unauthorized(w)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func elseAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := r.Header.Get("Authorization")
		if token == "" {
			next.ServeHTTP(w, r)
		} else if token != "s" {
			resp.Unauthorized(w)
			return
		} else {
			next.ServeHTTP(w, r)
		}
	})
}

// Refuse unless the request is a GET, or under /pub/.
func writeAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet {
			next.ServeHTTP(w, r)
			return
		}
		if r.Header.Get("Authorization") == "" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func publicPrefix(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/pub/") {
			next.ServeHTTP(w, r)
			return
		}
		if r.Header.Get("Authorization") == "" && !isPublic(r) {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func isPublic(r *http.Request) bool {
	return r.URL.Path == "/open"
}

func requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") == "" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func ok(w http.ResponseWriter, r *http.Request) {}

// A package constant shadowed by locals, and an outbound client call.
const field = "title"

func search(w http.ResponseWriter, r *http.Request) {
	_ = client.Fetch(r.Context(), "http://upstream")
	for _, field := range []string{"a", "b"} {
		_ = r.FormValue(field)
	}
}

func hdr(w http.ResponseWriter, r *http.Request) {
	field := os.Getenv("HEADER")
	_ = r.Header.Get(field)
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /", ok)
	mux.HandleFunc("GET /status", func(w http.ResponseWriter, r *http.Request) {
		if err := errors.New("x"); err != nil {
			writeError(w, err)
			return
		}
	})
	mux.HandleFunc("POST /login", handleLogin(nil))
	mux.Handle("GET /feed", optionalAuth(http.HandlerFunc(ok)))
	mux.Handle("POST /payments", idempotent(http.HandlerFunc(ok)))
	mux.Handle("GET /payments", paginate(http.HandlerFunc(ok)))
	mux.Handle("GET /logpass", logPass(http.HandlerFunc(ok)))
	mux.Handle("GET /else", elseAuth(http.HandlerFunc(ok)))
	mux.HandleFunc("GET /search", search)
	mux.HandleFunc("GET /hdr", hdr)
	registerAccount(mux)

	var admin http.Handler = http.HandlerFunc(ok)
	if os.Getenv("AUTH") == "on" {
		admin = requireAuth(admin)
	}
	mux.Handle("GET /admin", admin)

	docs := http.NewServeMux()
	docs.HandleFunc("GET /docs", ok)
	docs.HandleFunc("POST /docs", ok)
	mux.Handle("/docs", writeAuth(docs))

	pub := http.NewServeMux()
	pub.HandleFunc("GET /pub/info", ok)
	pub.HandleFunc("GET /open", ok)
	pub.HandleFunc("GET /priv/info", ok)
	mux.Handle("/x/", publicPrefix(pub))

	api := http.NewServeMux()
	api.HandleFunc("GET /items", ok)
	mux.Handle("/api/", requireAuth(api))
	mux.Handle("/legacy/", api)

	http.ListenAndServe(":8080", mux)
}
