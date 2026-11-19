package main

import (
	sw "example.com/petstore/go"
)

func main() {
	router := sw.NewRouter(sw.ApiHandleFunctions{})
	_ = router.Run(":8080")
}
