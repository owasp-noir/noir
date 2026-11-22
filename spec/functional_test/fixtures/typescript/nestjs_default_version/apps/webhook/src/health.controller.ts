import { Controller, Get, Version } from '@nestjs/common';

@Controller('v1/health-check')
export class HealthController {
  @Get()
  check() {
    return 'ok';
  }
}

@Controller(process.env.SUBPATH)
export class DynamicController {
  @Get('events')
  events() { return []; }
}

@Controller('status')
export class StatusController {
  @Get()
  status() { return 'ok'; }

  @Get('release')
  @Version(process.env.VERSION)
  release() { return 'ok'; }
}
