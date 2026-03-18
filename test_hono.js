// Simulate hono handler
const c = {
    req: {
        query: (x) => x,
        header: (x) => x,
        param: (x) => x,
        json: async () => ({}),
        parseBody: async () => ({})
    }
}
import { getCookie } from 'hono/cookie'
