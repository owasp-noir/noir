import { auth } from "@/lib/auth";

export async function GET(request: Request) {
  const session = await auth();
  if (!session) {
    return Response.json(await publicFeed());
  }
  if (!(await isMember(session))) return new AppError("unauthorized:feed").toResponse();
  return Response.json(await privateFeed(session));
}

export async function POST(request: Request) {
  const session = await auth();
  if (!session) {
    return Response.json(await publicFeed());
  }
  if (!(await isMember(session))) throw new Error("Unauthorized");
  return Response.json(await privateFeed(session));
}

export async function PUT(request: Request) {
  const session = await auth()
  if (!session) {
    return Response.json({ items: await publicItems() })
  }
  const showUnauthorizedBanner = false
  return Response.json({ items: await allItems(session), showUnauthorizedBanner })
}

export async function DELETE(request: Request) {
  const session = await auth();
  if (!session) throw new UnauthorizedError();
  return Response.json([]);
}
