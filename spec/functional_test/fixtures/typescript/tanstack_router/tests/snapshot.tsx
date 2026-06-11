import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/snapshot-only')({
  component: SnapshotOnlyComponent,
})

function SnapshotOnlyComponent() {
  return null
}
