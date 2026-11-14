package gin

type Engine struct{}

func (e *Engine) GET(path string, h func()) {}
