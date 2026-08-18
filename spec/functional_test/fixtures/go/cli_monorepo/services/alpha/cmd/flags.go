package main

import "flag"

// A second file of the same command: its flag must merge onto cli://alpha,
// and the file must show up in the endpoint's code paths.
func init() {
	flag.String("alpha-extra-flag", "", "alpha extra")
}
