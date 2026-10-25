package client

import (
	"context"
	"net/http"
)

func Fetch(ctx context.Context, url string) string {
	req, _ := http.NewRequestWithContext(ctx, "GET", url, nil)
	resp, _ := http.DefaultClient.Do(req)
	_ = req.URL.Query().Get("upstream_page")
	return resp.Header.Get("ETag")
}
