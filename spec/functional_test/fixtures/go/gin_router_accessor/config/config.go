package config

type Config struct{}

func (c *Config) Get(key string, h func()) string { return "" }

func Get() *Config { return &Config{} }
