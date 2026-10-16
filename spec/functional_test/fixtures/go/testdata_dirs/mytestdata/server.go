package mytestdata

import "net/http"

// "mytestdata" is not the toolchain-ignored "testdata" directory.
func Register() {
	http.HandleFunc("GET /real/mytestdata", func(w http.ResponseWriter, r *http.Request) {})
}
