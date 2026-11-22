import type { GlobalConfig } from 'payload'

export const SiteSettings: GlobalConfig = {
  slug: 'site-settings',
  fields: [
    {
      name: 'siteName',
      localized: true,
      type: 'text',
    },
    {
      name: 'maintenance',
      type: 'checkbox',
    },
  ],
}
