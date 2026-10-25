package api

import (
	"github.com/gin-gonic/gin"
	"github.com/gin-gonic/gin/binding"
	"github.com/test/gin-struct-handlers/model"
)

type ItemAPI struct{}

type ItemParams struct {
	Name     string `json:"name" form:"name"`
	Priority int    `json:"priority" form:"priority"`
	Extras   string `json:"extras" form:"-"`
	Owner    string
}

type paging struct {
	Limit int `form:"limit"`
	Since int `form:"since"`
}

func (a *ItemAPI) Health(c *gin.Context) {
	c.JSON(200, "ok")
}

func (a *ItemAPI) Public(c *gin.Context) {
	c.JSON(200, c.Query("q"))
}

func (a *ItemAPI) CreateMessage(c *gin.Context) {
	msg := model.Message{}
	if err := c.ShouldBindJSON(&msg); err != nil {
		return
	}
	c.JSON(200, msg)
}

func (a *ItemAPI) Signup(c *gin.Context) {
	c.JSON(200, c.PostForm("email"))
}

func (a *ItemAPI) Login(c *gin.Context) {
	c.JSON(200, c.PostForm("user"))
}

func (a *ItemAPI) ListItems(c *gin.Context) {
	params := &paging{Limit: 100}
	if err := c.MustBindWith(params, binding.Query); err == nil {
		c.JSON(200, params)
	}
}

func (a *ItemAPI) UpdateItem(c *gin.Context) {
	var in ItemParams
	if err := c.Bind(&in); err == nil {
		c.JSON(200, in)
	}
}

func (a *ItemAPI) GetClient(c *gin.Context) {
	var p struct {
		ID string `uri:"id"`
	}
	if err := c.ShouldBindUri(&p); err == nil {
		c.JSON(200, p)
	}
}
