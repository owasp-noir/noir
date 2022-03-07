package models

type AttackSurfaceEndpoint struct {
	Type        string `json:"type"`
	URL         string `json:"url"`
	Method      string `json:"method"`
	ContentType string `json:"contentType"`
	Body        string `json:"body"`
}
