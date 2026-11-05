import { Controller, Get } from '@nestjs/common'
import { Test } from '@nestjs/testing'

// A throwaway controller the e2e suite mounts on its own test app.
@Controller('e2e-probe')
class ProbeController {
  @Get('ping')
  ping() {
    return 'pong'
  }
}

describe('probe', () => {
  it('boots', async () => {
    await Test.createTestingModule({ controllers: [ProbeController] }).compile()
  })
})
