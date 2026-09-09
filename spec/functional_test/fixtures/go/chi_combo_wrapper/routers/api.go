package routers

import (
	"net/http"

	chi_middleware "github.com/go-chi/chi/v5/middleware"

	"example.com/combo/modules/web"
)

func reqToken() any { return nil }

func getToken(w http.ResponseWriter, r *http.Request)    {}
func deleteToken(w http.ResponseWriter, r *http.Request) {}
func getSecret(w http.ResponseWriter, r *http.Request)   {}
func putSecret(w http.ResponseWriter, r *http.Request)   {}
func delSecret(w http.ResponseWriter, r *http.Request)   {}
func listSecrets(w http.ResponseWriter, r *http.Request) {}
func robots(w http.ResponseWriter, r *http.Request)      {}
func assets(w http.ResponseWriter, r *http.Request)      {}

// Routes registers the API in gitea's style: Combo chains for one path
// with several verbs, and Methods for an explicit method list.
func Routes() *web.Router {
	m := web.NewRouter()
	_ = chi_middleware.GetHead

	m.Methods("GET, HEAD", "/robots.txt", robots)
	m.Methods("GET,HEAD,OPTIONS", "/assets/*", assets)

	m.Group("/user", func() {
		// Token introspection and deletion endpoint
		m.Combo("/token").
			Get(reqToken(), getToken).
			Delete(reqToken(), deleteToken)

		m.Group("/actions/secrets", func() {
			m.Get("", reqToken(), listSecrets)
			m.Combo("/{secretname}").
				Get(reqToken(), getSecret).
				Put(reqToken(), putSecret).
				Delete(reqToken(), delSecret)
		})
	})
	return m
}
