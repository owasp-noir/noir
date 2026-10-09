package main

import "github.com/labstack/echo/v4"

func listC(c echo.Context) error {
	qc := c.QueryParam("qc")
	_ = qc
	return nil
}

func main() {
	e := echo.New()
	e.GET("/a", listA)
	e.GET("/b", listB)
	e.GET("/c", listC)
	e.Start(":8080")
}

func listA(c echo.Context) error {
	qa := c.QueryParam("qa")
	_ = qa
	return nil
}

func listB(c echo.Context) error {
	qb := c.QueryParam("qb")
	_ = qb
	return nil
}
