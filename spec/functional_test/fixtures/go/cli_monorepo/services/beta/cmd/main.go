package main

import "flag"

func main() {
	flag.String("beta-only-flag", "", "beta")
	flag.Parse()
}
