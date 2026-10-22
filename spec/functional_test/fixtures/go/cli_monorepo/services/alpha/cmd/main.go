package main

import "flag"

// One go.mod, two commands. Naming both after the module merged their flag
// sets into a single cli://mono endpoint.
func main() {
	flag.String("alpha-only-flag", "", "alpha")
	flag.Parse()
}
