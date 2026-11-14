package client

import "github.com/go-resty/resty/v2"

func New() *resty.Client { return resty.New() }
