package metrics

// Not an Echo file: a path-shaped Group plus a verb lookalike must not
// become a route just because the group pre-pass reads this file.
func Setup() {
	g := client.Group("/internal")
	g.GET("/health", nil)
}
