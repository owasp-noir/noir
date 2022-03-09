package models

import (
	volt "github.com/hahwul/volt/format/har"
)

type AttackSurfaceEndpoint struct {
	Type        string             `json:"type"`
	URL         string             `json:"url"`
	Params      []volt.QueryString `json:"params"`
	Method      string             `json:"method"`
	ContentType string             `json:"contentType"`
	Body        string             `json:"body"`
}
