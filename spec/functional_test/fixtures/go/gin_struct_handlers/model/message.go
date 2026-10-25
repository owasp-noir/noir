package model

type Message struct {
	Title   string `json:"title"`
	Message string `json:"message"`
	Note    string
}
