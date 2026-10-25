import { Controller, Get, VERSION_NEUTRAL } from '@nestjs/common';

@Controller({ path: '/topics', version: '2' })
export class TopicsController {
  @Get()
  list() {
    return [];
  }
}

@Controller({ path: '.well-known/resource', version: VERSION_NEUTRAL })
export class WellKnownController {
  @Get()
  get() {
    return {};
  }
}
