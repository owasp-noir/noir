package request

import (
	"net/http"
	"strconv"
)

func RouteInt64Param(r *http.Request, param string) int64 {
	value, _ := strconv.ParseInt(r.PathValue(param), 10, 64)
	return value
}

func QueryFlag(r *http.Request, param string) bool {
	return r.URL.Query().Get(param) == "1"
}

func HasFlag(r *http.Request, param string) bool {
	values := r.URL.Query()
	_, ok := values[param]
	return ok
}
