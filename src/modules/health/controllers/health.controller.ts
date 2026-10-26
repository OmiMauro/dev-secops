import { Controller, Get } from '@nestjs/common';

/** Endpoint público para comprobar que la API está viva. */
@Controller('health')
export class HealthController {
  @Get()
  check() {
    return { status: 'ok' };
  }
}
