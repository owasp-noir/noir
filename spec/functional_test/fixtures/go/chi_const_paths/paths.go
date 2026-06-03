package app

// Route paths declared as package constants in a sibling file — the
// dominant real-world chi shape (e.g. drakkan/sftpgo). The analyzer
// resolves these across the package so the routes that reference them
// aren't dropped.
const (
	healthzPath = "/healthz"
	tokenPath   = "/api/v2/token"
	adminPath   = "/api/v2/admins"
)
