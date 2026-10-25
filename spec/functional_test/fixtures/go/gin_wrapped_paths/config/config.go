package config

// ApiUri is the REST API base path.
const ApiUri = "/api/v1"

type Config struct {
	site string
}

// BaseUri prefixes a configured site path; without one the resource is
// served as is.
func (c *Config) BaseUri(res string) string {
	if c.site == "" {
		return res
	}

	return c.BasePath() + res
}

func (c *Config) BasePath() string {
	return c.site
}

// Versioned always adds a fixed prefix.
func Versioned(p string) string {
	return "/v2" + p
}
