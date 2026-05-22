import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/empty')()

const unrelated = {
  loader: () => Secret.run(),
}
