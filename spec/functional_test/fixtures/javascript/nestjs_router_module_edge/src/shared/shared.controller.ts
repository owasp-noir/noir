import { Controller, Get } from '@nestjs/common';

@Controller('shared')
export class SharedController {
  @Get()
  root() { return 'shared'; }
}
