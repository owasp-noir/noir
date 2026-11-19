"use server";

import { auth } from "@/lib/auth";

export async function renameItem(id: string, name: string) {
  const session = await auth();
  if (!session?.user?.id) {
    throw new Error("Unauthorized");
  }

  await saveItem(id, name);
}

export async function listItems(id: string) {
  const item = await findItem(id);
  if (!item) {
    throw new Error("Unauthorized");
  }
  return item;
}

export async function historyItems() {
  const session = await auth();
  if (!session?.user) {
    return new AppError("unauthorized:item").toResponse();
  }
  return [];
}

export async function previewItems() {
  const session = await auth();
  if (!session?.user) {
    return new AppError("not_found:item").toResponse();
  }
  return [];
}

export async function shareItem({
  itemId,
  visibility,
}: {
  itemId: string;
  visibility: string;
}) {
  const session = await auth();
  if (!session?.user?.id) {
    throw new Error("Unauthorized");
  }

  await saveVisibility(itemId, visibility);
}
