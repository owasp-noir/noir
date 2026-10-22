import { Controller, Get } from '@midwayjs/core';

@Controller('/shop')
export class StatusController {
  @Get('/status')
  async status() {
    return 'ok';
  }
}
