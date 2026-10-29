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

func main() {
	e := echo.New()
	e.POST("/login", Login)
	e.POST("/direct", Direct)
	e.Start(":8080")
}
