import { Controller, Get } from '@nestjs/common';

/** Public endpoint to check that the API is alive. */
@Controller('health')
export class HealthController {
  @Get()
  check() {
    return { status: 'ok' };
  }
}
