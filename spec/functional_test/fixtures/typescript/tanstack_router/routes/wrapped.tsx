import { createFileRoute } from '@tanstack/react-router'

// A formatter-wrapped multi-line createFileRoute call with a trailing
// comma must still be matched.
export const Route = createFileRoute(
  '/wrapped',
)({
  component: Wrapped,
})

function Wrapped() {
  return null
}
