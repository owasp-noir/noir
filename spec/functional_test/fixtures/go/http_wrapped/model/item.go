package model

type ItemRequest struct {
	Title    string `json:"title"`
	Archived *bool  `json:"archived,omitempty"`
	Secret   string `json:"-"`
}
