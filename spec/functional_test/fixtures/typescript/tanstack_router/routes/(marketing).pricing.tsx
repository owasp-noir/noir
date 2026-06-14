import { createFileRoute } from '@tanstack/react-router'

// A `(group)` route-group segment is organizational only — it must be
// stripped from the URL, so this serves `/pricing`, not
// `/(marketing)/pricing`.
export const Route = createFileRoute('/(marketing)/pricing')({
  component: Pricing,
})

function Pricing() {
  return null
}
