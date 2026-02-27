// Regression test fixture for HTTP client calls in test files.
//
// noir must NOT extract routes from client-side HTTP calls.
// These patterns were previously detected as false-positive server routes:
//
//   frisby.get(`${API_URL}/Recycles`)        → GET /http:/localhost:3000/api/Recycles
//   frisby.del(`${API_URL}/Recycles/1`, ...) → DELETE /http:/localhost:3000/api/Recycles/1
//   axios.get('http://localhost:3000/users')  → GET /http:/localhost:3000/users
//
// All calls below should produce ZERO endpoints.

import frisby = require('frisby')
const axios = require('axios')

const API_URL = 'http://localhost:3000/api'
const BASE_URL = 'http://localhost:3000'

describe('/api/Recycles', () => {
  // frisby.get with template literal where the constant is an http:// URL
  it('GET all recycles', () => {
    return frisby.get(`${API_URL}/Recycles`)
      .expect('status', 200)
  })

  // frisby.post with template literal
  it('POST new recycle', () => {
    return frisby.post(`${API_URL}/Recycles`, {
      body: { quantity: 200 }
    })
      .expect('status', 201)
  })

  // frisby.put with template literal and item ID
  it('PUT update recycle is forbidden', () => {
    return frisby.put(`${API_URL}/Recycles/1`, {
      body: { quantity: 100 }
    })
      .expect('status', 401)
  })

  // frisby.del with template literal and item ID
  it('DELETE recycle is forbidden', () => {
    return frisby.del(`${API_URL}/Recycles/1`, {})
      .expect('status', 401)
  })

  // axios.get with a plain http:// string
  it('axios GET does not leak as a route', async () => {
    const res = await axios.get(`${BASE_URL}/users`)
    return res
  })

  // axios.post with a plain http:// string
  it('axios POST does not leak as a route', async () => {
    await axios.post('http://localhost:3000/api/orders', { item: 'test' })
  })
})
