export async function renderShare(ctx, next) {
  const { shareId, documentSlug } = ctx.params;
  ctx.body = { shareId, documentSlug };
}
