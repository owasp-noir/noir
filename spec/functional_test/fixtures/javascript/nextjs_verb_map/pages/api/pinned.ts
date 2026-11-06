import type { NextApiRequest, NextApiResponse } from 'next'
import { HttpMethod, respondToMatchingRequest } from '../../utils/respond'

const handler = (req: NextApiRequest, res: NextApiResponse): void => {
  respondToMatchingRequest<Payload>(HttpMethod.GET, req, res, { ok: true })
}

export default handler
