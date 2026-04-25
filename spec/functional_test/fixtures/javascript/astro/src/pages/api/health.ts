// No explicit verb exports — falls back to the catch-all handler set.
export async function ALL() {
    return new Response('ok');
}
