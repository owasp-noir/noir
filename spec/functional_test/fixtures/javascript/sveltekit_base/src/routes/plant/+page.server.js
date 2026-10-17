export const actions = {
  default: async ({ request }) => {
    await request.formData();
  }
};
