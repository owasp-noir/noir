// No explicit verb exports — falls back to the catch-all handler set.
export async function ALL({ request }) {
    return new Response('ok');
}
