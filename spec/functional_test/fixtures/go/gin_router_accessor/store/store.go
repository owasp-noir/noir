package store

type Store struct{}

func (s *Store) Delete(path string, h func()) error { return nil }

func Get() *Store { return &Store{} }
