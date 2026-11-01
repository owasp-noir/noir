import { Controller, Get, UseGuards, applyDecorators } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { JwtAuthGuard } from './jwt-auth.guard';
import { ThrottlerGuard } from '@nestjs/throttler';
import { AuthGuard } from '@nestjs/passport';

export function Auth() {
  return applyDecorators(
    UseGuards(
      JwtAuthGuard,
    ),
    ApiBearerAuth(),
  );
}

@Controller('cases')
export class CasesController {
  @Get('multiline')
  @UseGuards(
    ThrottlerGuard,
    JwtAuthGuard,
  )
  multiline() { return 1; }

  @Get('throttle-only')
  @UseGuards(
    ThrottlerGuard,
  )
  throttleOnly() { return 1; }

  // @UseGuards(JwtAuthGuard)
  @Get('commented-guard')
  commentedGuard() { return 1; }

  @ApiOperation({ description: 'call it behind @UseGuards(JwtAuthGuard) upstream' })
  @Get('guard-in-string')
  guardInString() { return 1; }

  @Get('roles')
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  roles() { return 1; }

  @UseGuards(JwtAuthGuard) @Get('one-line') oneLine() { return 1; }
  @Get('after-one-line') afterOneLine() { return 1; }

  @Get('bundle')
  @Auth()
  bundle() { return 1; }
}

@UseGuards(JwtAuthGuard)
@Controller('guarded')
export class GuardedController {
  @Get()
  index() { return 1; }
}

@Controller('open')
export class OpenController {
  @Get()
  index() { return 1; }
}
