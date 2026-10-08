package users

type ListParams struct {
	PageSize int    `query:"limit"`
	Cursor   string
	Tenant   string `header:"X-Tenant"`
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
