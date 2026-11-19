package main

func (s *Server) routes() {
	r := s.engine
	r.GET("/v2/users", s.handlers.User.List)
	r.GET("/v2/orders", s.orders.List)
}
