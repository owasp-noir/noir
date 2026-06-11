package remote

import (
	"context"

	"github.com/cloudwego/hertz/pkg/app"
)

func Feed(c context.Context, ctx *app.RequestContext) {
	item := loadFeed(ctx)
	ctx.JSON(200, item)
}

func loadFeed(ctx *app.RequestContext) string {
	return ""
}
