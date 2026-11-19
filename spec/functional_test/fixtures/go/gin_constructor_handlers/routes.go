package main

func (s *Server) routes() {
	r := s.engine
	r.GET("/v2/users", s.handlers.User.List)
	r.GET("/v2/orders", s.orders.List)
	r.GET("/questions/:id", s.questions.Info)
	r.GET("/questions/:id/:title", s.questions.Info)
	r.GET("/questions/:id/:title/:answerid", s.questions.Info)
}
