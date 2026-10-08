export default async (req: Request) => {
  const { message } = await req.json();
  return Response.json({ pong: message });
};
