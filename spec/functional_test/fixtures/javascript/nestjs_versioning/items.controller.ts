import { Controller, Get, Query, Version } from '@nestjs/common';

// Compact one-line members: no line holds a bare `}`, so the decorator
// block above `b` and `c` must stop at the end of the previous body.
@Controller('items')
export class ItemsController {
  @Version('2') @Get('a') a() { return 1 }
  @Get('b') b(@Query('q') q: string) { return 2 }
  @Get('c') c() { return 3 } @Version('4') @Get('d') d() { return 4 }
}
