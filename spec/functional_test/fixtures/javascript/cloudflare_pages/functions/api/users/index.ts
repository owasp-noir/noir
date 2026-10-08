export const onRequestPost: PagesFunction = async (context) => {
  const { request } = context;
  const { name, email } = await request.json();
  return Response.json({ name, email }, { status: 201 });
};

// Every method without a dedicated export above.
export const onRequest: PagesFunction = async ({ request }) => {
  return new Response(`${request.method} not allowed`, { status: 405 });
};
