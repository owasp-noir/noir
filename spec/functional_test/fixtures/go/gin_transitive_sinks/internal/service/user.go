package service

import (
	"os/exec"

	"example.com/app/internal/repo"
)

type Runner interface {
	Run(q string) string
}

type RunnerA struct{}

func (a *RunnerA) Run(q string) string {
	_ = exec.Command("sh", "-c", q).Run()
	return q
}

type RunnerB struct{}

func (b *RunnerB) Run(q string) string {
	_ = exec.Command("sh", "-c", q).Run()
	return q
}

type UserService struct {
	repo *repo.UserRepo
}

func NewUserService(r *repo.UserRepo) *UserService {
	return &UserService{repo: r}
}

func (s *UserService) RunExport(target string) error {
	return exec.Command("export.sh", target).Run()
}

func (s *UserService) Search(name string) ([]string, error) {
	return s.repo.SearchByName(name)
}

func (s *UserService) PingA(n int) string {
	if n <= 0 {
		return "done"
	}
	return s.PingB(n - 1)
}

func (s *UserService) PingB(n int) string {
	return s.PingA(n - 1)
}

func (s *UserService) Status() string {
	return "ok"
}
