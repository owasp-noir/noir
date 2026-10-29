package main

import "net/http"

func moreRoutes() {
	mux := http.NewServeMux()
	mux.Handle("/nestedskip", authNestedSkip(http.HandlerFunc(list)))
	mux.Handle("/csrfexempt", authCSRFExempt(http.HandlerFunc(list)))
	mux.Handle("/csrfparam", authCSRFParam(http.HandlerFunc(list)))
	mux.Handle("/gofunc", authGoFunc(http.HandlerFunc(list)))
	mux.HandleFunc("/loginpost", loginPost(verify))
	http.ListenAndServe(":8080", mux)
}

func run(fn func()) { fn() }

// Public skip whose hand-on sits in a multi-line closure inside the if arm.
func authNestedSkip(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" {
			run(func() {
				next.ServeHTTP(w, r)
			})
			return
		}
		if r.Header.Get("Authorization") == "" {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func csrfExempt(r *http.Request) bool { return false }

// Session check joined by && to a CSRF-exempt test.
func authCSRFExempt(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Cookie") == "" && !csrfExempt(r) {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func validSession(r *http.Request, csrfKey string) bool { return false }

// Session validation that also takes a csrf key.
func authCSRFParam(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !validSession(r, "k") {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func audit(r *http.Request) {}

// A goroutine before the check.
func authGoFunc(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		go func() {
			audit(r)
		}()
		if r.Header.Get("Authorization") == "" {
			http.Error(w, "no", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func verify(r *http.Request) bool { return false }

// Login factory: request-shaped callback called under a method test.
func loginPost(check func(*http.Request) bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			if !check(r) {
				http.Error(w, "bad password", http.StatusUnauthorized)
				return
			}
		}
		w.WriteHeader(http.StatusOK)
	}
}

