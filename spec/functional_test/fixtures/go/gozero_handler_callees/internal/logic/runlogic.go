package logic

import (
	"context"
	"os/exec"
)

type Req struct {
	Cmd string `json:"cmd"`
}

type RunLogic struct{ ctx context.Context }

func NewRunLogic(ctx context.Context) *RunLogic { return &RunLogic{ctx: ctx} }

func (l *RunLogic) Run(req *Req) error {
	return exec.Command("sh", "-c", req.Cmd).Run()
}
