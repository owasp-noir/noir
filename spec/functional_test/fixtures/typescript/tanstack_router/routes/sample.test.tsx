import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/test-only')({
  component: TestOnlyComponent,
})

function TestOnlyComponent() {
  return null
}
