package users

import "context"

//encore:service
type Service struct{}

//encore:api auth method=GET path=/users
func (s *Service) List(ctx context.Context, p *ListParams) (*UserList, error) {
	return &UserList{}, nil
}

//encore:api auth method=PUT,PATCH path=/users/:id
func (s *Service) Update(ctx context.Context, id int, p *UpdateParams) (*User, error) {
	return &User{}, nil
}

// Create has a request payload and no method, so it defaults to POST.
//
//encore:api private
func Create(ctx context.Context, p *UpdateParams) (*User, error) {
	return &User{}, nil
}
