import { createFileRoute } from '@tanstack/react-router'
import { useState } from 'react'

// Regression guard: a route file that imports `react` (as real TanStack
// Router pages do) must NOT be skipped by the client-side-framework
// filter — its route is a definition here, not an outbound API call.
export const Route = createFileRoute('/react-page')({
  component: ReactPage,
})

function ReactPage() {
  const [count] = useState(0)
  return count
}
