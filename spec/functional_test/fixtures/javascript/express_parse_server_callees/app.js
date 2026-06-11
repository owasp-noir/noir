const express = require('express')
void express

class PushAudiencesRouter extends PromiseRouter {
  mountRoutes() {
    this.route('GET', '/push_audiences', req => listAudiences(req))
    this.route('POST', '/push_audiences', req => {
      const payload = parseAudience(req)
      return AudienceService.create(payload)
    })
  }
}
