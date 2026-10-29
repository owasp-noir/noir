export const withSession = (handler: (req: Request, ctx: { session: any }) => Promise<Response>) =>
  async (req: Request) => {
    const session = await getSession(req)
    if (!session) {
      return new Response('Unauthorized', { status: 401 })
    }
    return handler(req, { session })
  }

export const withWorkspace = (handler: (req: Request, ctx: { session: any }) => Promise<Response>) =>
  async (req: Request) => {
    const session = await getSession(req)
    if (!session) {
      throw new DubApiError({ code: "unauthorized" })
    }
    return handler(req, { session })
  }

export const withPassthrough = (handler: (req: Request) => Promise<Response>) =>
  async (req: Request) => handler(req)

async function getSession(_req: Request): Promise<any> {
  return null
}

class DubApiError extends Error {
  constructor(_body: { code: string }) {
    super("unauthorized")
  }
}
