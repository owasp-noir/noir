package export

import (
	"github.com/hahwul/noir/pkg/models"
	volt "github.com/hahwul/volt/format/har"
)

func ASEtoHAR(ase []models.AttackSurfaceEndpoint) volt.HARObject {
	var harObject volt.HARObject
	harObject = volt.HARObject{
		Log: volt.HARLog{
			Version: "",
			Entries: []volt.Entry{},
		},
	}
	for _, endpoint := range ase {
		mime := ""
		switch endpoint.ContentType {
		case "json":
			mime = "application/json"
			break
		case "form":
			mime = "application/x-www-form-urlencoded"
			break
		}

		entry := volt.Entry{
			Request: volt.Request{
				Method: endpoint.Method,
				URL:    endpoint.URL,
				PostData: volt.PostData{
					Text:     endpoint.Body,
					MimeType: mime,
				},
			},
		}
		harObject.Log.Entries = append(harObject.Log.Entries, entry)
	}
	return harObject
}
