package cmd

import (
	"strings"

	"github.com/spf13/cobra"
)

// Braces in a rune and an interpreted string are not blocks either.
func isOpen(r rune) bool { return r == '{' }

func trimBrace(x string) string { return strings.TrimSuffix(x, "{") }

var usersExportCmd = &cobra.Command{Use: "export"}
