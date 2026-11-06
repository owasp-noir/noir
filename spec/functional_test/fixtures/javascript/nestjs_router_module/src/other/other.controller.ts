import { Controller, Get } from '@nestjs/common';

@Controller('other')
export class OtherController {
  @Get()
  root(): string { return 'other'; }
}
