// 사용자 API 엔드포인트 — 한국어 주석으로 멀티바이트 문자를 포함합니다.
// これは日本語のコメントです。マルチバイト文字が含まれています。
// Emoji también cuentan: 🚀🔥 — los acentos y símbolos ocupan más de un byte.

export async function GET({ url }) {
  return new Response("list");
}

export async function POST({ request }) {
  return new Response("create");
}
