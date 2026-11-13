package main

// Look-alike calls in the same package that are not routes: a KV store
// keyed by paths, an outbound peer client and a legacy router type with
// gin-style verbs. None of them is the chi wrapper.

type store struct{ data map[string]string }

func newStore() *store { return &store{data: map[string]string{}} }

func (s *store) Get(key string) string { return s.data[key] }

type peerClient struct{}

func (p *peerClient) Post(path string, body []byte) error { return nil }

type legacyMux struct{}

func (l *legacyMux) GET(path string, h func()) {}

func sync(kv *store, peer *peerClient, body []byte) {
	kv.Get("/config/feature")
	peer.Post("/sync", body)
	m := &legacyMux{}
	m.GET("/legacy", func() {})
}
