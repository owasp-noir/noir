package users

type ListParams struct {
	PageSize int    `query:"limit"`
	Cursor   string
	Tenant   string `header:"X-Tenant"`
	// `json:"-"` only drops a field whose location is the JSON body.
	Auth   string `header:"Authorization" json:"-"`
	Offset int    `json:"-"`
}

// Same name as shared.Other: must not be bound to `*shared.Other`.
type Other struct {
	Secret string
}

type UpdateParams struct {
	DisplayName string `json:"display_name"`
	Email       string
	RequestID   string `header:"X-Request-ID"`
	Internal    string `json:"-"`
	secret      string
}

type User struct{}

type UserList struct{}
