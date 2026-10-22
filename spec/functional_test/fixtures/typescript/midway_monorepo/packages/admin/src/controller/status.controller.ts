import { Controller, Get } from '@midwayjs/core';

@Controller('/admin')
export class StatusController {
  @Get('/status')
  async status() {
    return 'ok';
  }
}
