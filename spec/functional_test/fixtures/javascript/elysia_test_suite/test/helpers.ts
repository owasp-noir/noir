import { describe, expect, it } from 'bun:test'
import { Elysia } from 'elysia'

// Plain file name, but a suite under test/.
describe('helpers', () => {
  const mock = new Elysia().get('/elysia-suite-only', () => 'x')

  it('responds', async () => {
    const res = await mock.handle(new Request('http://localhost/elysia-suite-only'))
    expect(res.status).toBe(200)
  })
})
