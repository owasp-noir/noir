import { Controller, Get } from '@nestjs/common';
import { RouteKey } from './enum';

@Controller(RouteKey.Asset)
export class AssetsController {
  @Get('statistics')
  statistics() {
    return {};
  }
}
