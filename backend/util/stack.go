package util

type Stack[T any] struct {
	items []T
}

func NewStack[T any]() *Stack[T] {
	return &Stack[T]{
		items: make([]T, 0),
	}
}

func (s *Stack[T]) Size() int {
	return len(s.items)
}

// Pop is unchecked so will throw if its empty
func (s *Stack[T]) Pop() T {
	item := s.items[len(s.items)-1]
	s.items = s.items[:len(s.items)-1]
	return item
}

func (s *Stack[T]) Push(i T) {
	s.items = append(s.items, i)
}

func (s *Stack[T]) IsEmpty() bool {
	return len(s.items) == 0
}

func (s *Stack[T]) Head() *T {
	return &s.items[len(s.items)-1]
}

func (s *Stack[T]) Items() []T {
	return s.items
}

func (s *Stack[T]) Clear() {
	clear(s.items)
}
