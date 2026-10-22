package main

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"example.com/app/setting"
)

// Router takes its middleware after the closure, the way Gitea's
// web.Router does: Group(pattern, fn, middlewares...).
func routes(m *Router) {
	reqSignIn := verifyAuth(&Options{SignInRequired: true})
	optSignIn := verifyAuth(&Options{SignInRequired: setting.RequireSignInView})
	reqSignOut := verifyAuth(&Options{SignOutRequired: true})

	m.Get("/login", reqSignOut, login)
	m.Group("/explore", func() {
		m.Get("/repos", exploreRepos)
	}, optSignIn)

	m.Group("/user", func() {
		m.Get("", currentUser)
		m.Group("/settings", func() {
			m.Get("", settings)
		})
	}, tokenRequiresScopes("user"), reqToken())

	m.Group("/repos", func() {
		m.Get("/{id}", tokenRequiresScopes("repo"), getRepo)
		m.Combo("/{id}/topics").Get(listTopics).
			Delete(reqToken(), reqRepoAdmin(), deleteTopics)
		m.Post("/{id}/star", reqSignIn, star)
		m.Get("/{id}/stats", requireStatsView(), stats)
	}, tokenRequiresScopes("repo"), sudo())

	m.Group("/admin", func() {
		m.Get("/users", listUsers)
	},
		reqToken(), reqSiteAdmin(),
	)
}

func chiRoutes(r chi.Router) {
	r.Get("/status", status)
	r.Group(func(r chi.Router) {
		r.Use(reqToken())
		r.Get("/me", currentUser)
	})
	r.With(reqToken()).Get("/feed", feed)
	r.Get("/public", status)
}

func reqToken() func(ctx *Context) {
	return func(ctx *Context) {
		if ctx.IsSigned {
			return
		}
		ctx.Error(http.StatusUnauthorized, "token is required")
	}
}

// Checks a token's scope, and lets a request without a token through.
func tokenRequiresScopes(scope string) func(ctx *Context) {
	return func(ctx *Context) {
		scopes, ok := tokenScopes(ctx)
		if !ok {
			return
		}
		if !hasScope(scopes, scope) {
			ctx.Error(http.StatusForbidden, "token does not have the required scope")
		}
	}
}

// Only refuses a caller who asks to act as another user.
func sudo() func(ctx *Context) {
	return func(ctx *Context) {
		target := ctx.Req.URL.Query().Get("sudo")
		if len(target) > 0 {
			if !ctx.IsAdmin {
				ctx.Error(http.StatusForbidden, "only administrators may sudo")
				return
			}
		}
	}
}

// Refuses anonymous callers only when the deployment turns it on.
func requireStatsView() func(ctx *Context) {
	return func(ctx *Context) {
		if setting.RequireSignInView && !ctx.IsSigned {
			ctx.Error(http.StatusUnauthorized, "sign in required")
		}
	}
}

func reqSiteAdmin() func(ctx *Context) {
	return func(ctx *Context) {
		if !ctx.IsAdmin {
			ctx.Error(http.StatusForbidden, "site admin only")
		}
	}
}

func reqRepoAdmin() func(ctx *Context) {
	return func(ctx *Context) {
		if !ctx.CanAdminRepo() {
			ctx.Error(http.StatusForbidden, "repository admin only")
		}
	}
}

// One factory serves sign-in, sign-out and optional pages; only what the
// call site's options turn on refuses the caller.
func verifyAuth(options *Options) func(ctx *Context) {
	return func(ctx *Context) {
		if ctx.IsSigned && ctx.MustChangePassword {
			ctx.Error(http.StatusUnauthorized, "password change required")
			return
		}
		if options.SignOutRequired && ctx.IsSigned {
			ctx.Redirect("/")
			return
		}
		if options.SignInRequired && !ctx.IsSigned {
			ctx.RedirectForLogin()
			return
		}
	}
}

type Options struct {
	SignInRequired  bool
	SignOutRequired bool
}

type Context struct {
	IsSigned           bool
	IsAdmin            bool
	MustChangePassword bool
	Req                *http.Request
}

func (ctx *Context) Error(status int, message string) {}
func (ctx *Context) Redirect(location string)         {}
func (ctx *Context) RedirectForLogin()                {}
func (ctx *Context) CanAdminRepo() bool               { return ctx.IsAdmin }

type Router struct{ chi.Router }

func (m *Router) Group(pattern string, fn func(), middlewares ...any) {}
func (m *Router) Get(pattern string, h ...any) *Router               { return m }
func (m *Router) Post(pattern string, h ...any) *Router              { return m }
func (m *Router) Delete(h ...any) *Router                            { return m }
func (m *Router) Combo(pattern string, h ...any) *Router             { return m }

func tokenScopes(ctx *Context) ([]string, bool)       { return nil, false }
func hasScope(scopes []string, scope string) bool     { return false }
func login(ctx *Context)                              {}
func exploreRepos(ctx *Context)                       {}
func currentUser(ctx *Context)                        {}
func settings(ctx *Context)                           {}
func getRepo(ctx *Context)                            {}
func listTopics(ctx *Context)                         {}
func deleteTopics(ctx *Context)                       {}
func star(ctx *Context)                               {}
func stats(ctx *Context)                              {}
func listUsers(ctx *Context)                          {}
func status(w http.ResponseWriter, r *http.Request)   {}
func feed(w http.ResponseWriter, r *http.Request)     {}
