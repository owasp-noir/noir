import { Controller, Get, Post, Body, Param } from '@nestjs/common'

// URI versioning via a single version string.
@Controller({ path: 'cats', version: '1' })
export class CatsControllerV1 {
  @Get()
  list() {
    return []
  }

  @Get(':id')
  byId(@Param('id') id: string) {
    return { id }
  }
}

// URI versioning across multiple versions on one controller.
@Controller({ path: 'cats', version: ['2', '3'] })
export class CatsControllerV2 {
  @Post()
  create(@Body() body: unknown) {
    return body
  }
}

// VERSION_NEUTRAL — emit without a version prefix.
@Controller({ path: 'health', version: 'VERSION_NEUTRAL' })
export class HealthController {
  @Get()
  ping() {
    return { ok: true }
  }
}

// Method-level versioning overrides, rather than stacks on top of,
// controller-level URI versioning.
@Controller({ path: 'dogs', version: '1' })
export class DogsController {
  @Version('2')
  @Get('override')
  override() {
    return []
  }
}
