package main

import (
	"log"

	reference "example.org/reference/src"
)

func main() { log.Fatal(reference.Engine().Run(":3000")) }
