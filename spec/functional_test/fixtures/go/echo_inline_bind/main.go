package main

import "github.com/labstack/echo/v4"

type CreateUser struct {
	Name  string `json:"name" form:"name"`
	Email string `json:"email" form:"email"`
}

type ListUsers struct {
	Page   int    `query:"page"`
	Search string `query:"search"`
}

// control: a named handler, read through the bound struct
func createNamed(c echo.Context) error {
	var in CreateUser
	return c.Bind(&in)
}

func listNamed(c echo.Context) error {
	var in ListUsers
	return c.Bind(&in)
}

func main() {
	e := echo.New()
	e.POST("/named", createNamed)
	e.GET("/named", listNamed)

	// the same two handlers written inline
	e.POST("/inline", func(c echo.Context) error {
		var in CreateUser
		return c.Bind(&in)
	})
	e.GET("/inline", func(c echo.Context) error {
		var in ListUsers
		return c.Bind(&in)
	})
	// upload + cookie with a trailing call on the line
	e.POST("/upload", func(c echo.Context) error {
		_, _ = c.FormFile("avatar")
		return nil
	})
	_ = e.Start(":1323")
}
