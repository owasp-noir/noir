import { Controller, Get } from 'routing-controllers';

// `@Controller` (not JSON) with no prefix.
@Controller()
export class HealthController {
  @Get('/health')
  health() {
    return 'ok';
  }
}
