package main

import (
	"flag"
	"fmt"
	"os"
)

func main() {
	name := flag.String("name", "world", "name to greet")
	verbose := flag.Bool("verbose", false, "enable verbose output")
	flag.Parse()

	token := os.Getenv("API_TOKEN")
	command := os.Args[1]

	fmt.Println(*name, *verbose, token, command)
}
