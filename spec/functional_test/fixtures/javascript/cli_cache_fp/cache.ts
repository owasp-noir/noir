// Regression guard: "cache"/"cacheName" contain the letters c-a-c, which used
// to count as CLI-library evidence. This is a plain library module: its
// `options: {` parameter type and `process.env` read are not CLI flags or
// env inputs.
export const cache = (options: {
  cacheName: string,
  wait: boolean,
}) => {
  const ttl = process.env.CACHE_TTL;
  return { name: options.cacheName, ttl };
};
