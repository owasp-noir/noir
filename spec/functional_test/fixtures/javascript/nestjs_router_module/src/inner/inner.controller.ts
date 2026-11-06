import { Controller, Get } from '@nestjs/common';

@Controller()
export class InnerController {
  @Get()
  root(): string { return 'inner'; }
}
