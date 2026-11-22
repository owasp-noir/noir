package input

import "github.com/gin-gonic/gin"

type Common struct {
	Cursor string `form:"cursor" json:"cursor,omitempty"`
}

type Options struct {
	*Common
	Limit    int                    `form:"limit" json:"limit,omitempty"`
	Internal string                 `form:"-" json:"-"`
	Trace    string                 `header:"X-Trace" json:",omitempty"`
	Group    struct{ Label string } `json:"group"`
	private  string                 `json:"internal"`
}

func Read(c *gin.Context, dst any) error {
	return decode(dst, c)
}

func decode(dst any, c *gin.Context) error {
	return c.ShouldBindJSON(dst)
}
