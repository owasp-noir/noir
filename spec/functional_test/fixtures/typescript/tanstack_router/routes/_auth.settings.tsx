import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/_auth/settings')({
  validateSearch: (search: Record<string, unknown>) => ({
    tab: String(search.tab ?? 'profile'),
    page: Number(search.page ?? 1),
  }),
  component: SettingsComponent,
})

function SettingsComponent() {
  return null
}
