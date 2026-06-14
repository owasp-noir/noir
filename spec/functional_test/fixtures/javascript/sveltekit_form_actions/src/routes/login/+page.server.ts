import type { Actions } from './$types';

// SvelteKit form actions — inbound POST handlers at the page's URL.
export const actions: Actions = {
  default: async ({ request, cookies }) => {
    const data = await request.formData();
    const email = data.get('email');
    return { email };
  },
};
