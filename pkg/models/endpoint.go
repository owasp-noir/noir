package models

type Endpoint struct {
	URL         string `json:"url"`
	Method      string `json:"method"`
	ContentType string `json:"contentType"`
	Body        string `json:"body"`
}
