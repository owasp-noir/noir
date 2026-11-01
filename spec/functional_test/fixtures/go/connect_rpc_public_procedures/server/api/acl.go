package api

// PublicMethods are reachable without credentials.
var PublicMethods = map[string]struct{}{
	// Sign-in must work before a session exists.
	"/notes.api.AuthService/SignIn": {},
	"/notes.api.NoteService/ListNotes": {},
}

// BootstrapMethods stay public even on a private instance.
var BootstrapMethods = map[string]struct{}{
	"/notes.api.AuthService/SignIn": {},
}

func IsPublicMethod(procedure string) bool {
	_, ok := PublicMethods[procedure]
	return ok
}

func IsBootstrapMethod(procedure string) bool {
	_, ok := BootstrapMethods[procedure]
	return ok
}
