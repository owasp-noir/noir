package legacy

import (
	"github.com/gin-gonic/gin"

	other "example.com/ginaccessor/legacy/gin"
)

var v1 = &other.Engine{}

// A same-named accessor declared to return another package's `Engine`,
// not gin's.
func V1() *other.Engine { return v1 }

func Payload() gin.H { return gin.H{} }
