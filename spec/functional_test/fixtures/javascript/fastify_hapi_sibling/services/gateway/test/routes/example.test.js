'use strict'
const { test } = require('node:test')
const assert = require('node:assert')
const { build } = require('../helper')
test('example is loaded', async (t) => {
  const app = await build(t)
  const res = await app.inject({ url: '/example' })
  assert.equal(res.payload, 'this is an example')
})
