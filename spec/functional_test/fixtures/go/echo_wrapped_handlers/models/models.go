package models

type Base struct {
	ID int `json:"id"`
}

type Note struct {
	Base

	Title string `json:"title"`
	Text  string `json:"text"`
	Owner string `json:"-"`
}
