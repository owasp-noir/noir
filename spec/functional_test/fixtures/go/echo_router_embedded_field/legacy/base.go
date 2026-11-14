package legacy

// An `Echo` field that is not an echo router.
type Printer struct{}

func (p *Printer) GET(path string, h func()) {}

type Base struct {
	Echo *Printer
}
