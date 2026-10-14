export default defineEventHandler((event) => {
  return proxyRequest(event, 'https://upstream.example.com' + event.path)
})
