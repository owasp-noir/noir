import { describe, expect, it } from 'bun:test'
import { Elysia } from 'elysia'

describe('elysia', () => {
  const mock = new Elysia().get('/elysia-test-only', () => 'x').post('/elysia-test-post', () => 'y')

  it('responds', async () => {
    const res = await mock.handle(new Request('http://localhost/elysia-test-only'))
    expect(res.status).toBe(200)
  })
})
