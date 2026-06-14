import router from '@adonisjs/core/services/router'
import env from '#start/env'

// Real registrations.
router.get('/health', () => ({ ok: true }))
// `router.on('/path').render/.redirect` — always a GET endpoint.
router.on('/about').render('pages/about')
router.on('/terms').redirect('/legal/terms')

// NONE of the calls below are routes — they are method calls shaped like a
// registration but rooted on a non-router receiver, and must NOT produce
// endpoints (env var read, session read, Lucid query terminator).
const stripeKey = env.get('STRIPE_SECRET_KEY')

export default class CleanupController {
  async handle({ session }: any) {
    const plan = session.get('plan')
    await SessionLog.query().whereNotNull('logoutAt').delete('*')
    return { stripeKey, plan }
  }
}
