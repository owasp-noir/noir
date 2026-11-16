function pingA(n) {
  if (n <= 0) return 'done';
  return pingB(n - 1);
}

function pingB(n) {
  return pingA(n - 1);
}

function slugify(title) {
  return String(title || '').toLowerCase().replace(/\s+/g, '-');
}

module.exports = { pingA, slugify };
