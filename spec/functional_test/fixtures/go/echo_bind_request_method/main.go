package main

import "github.com/labstack/echo/v4"

type loginRequest struct {
	User struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	} `json:"user"`
}

// A bind method on the request type, as in the Echo RealWorld handlers.
func (r *loginRequest) bind(c echo.Context) error {
	if err := c.Bind(r); err != nil {
		return err
	}
	return nil
}

type unusedRequest struct{ Other string }

func (r *unusedRequest) bind(c echo.Context) error { return c.Bind(r) }

func Login(c echo.Context) error {
	req := &loginRequest{}
	if err := req.bind(c); err != nil {
		return err
	}
	return nil
}

func Direct(c echo.Context) error {
	req := &loginRequest{}
	if err := c.Bind(req); err != nil {
		return err
	}
	return nil
}

type resource struct{ fresh func() any }
type draft struct {
	Title string `json:"title"`
}
type reply struct {
	Text string `json:"text"`
}

func (res *resource) create(c echo.Context) error {
	value := res.fresh()
	return c.Bind(value)
}

func main() {
	e := echo.New()
	e.POST("/login", Login)
	e.POST("/direct", Direct)
	drafts := &resource{fresh: func() any { return &draft{} }}
	replies := &resource{fresh: func() any { return &reply{} }}
	e.POST("/drafts", drafts.create)
	e.POST("/replies", replies.create)
	e.Start(":8080")
}
