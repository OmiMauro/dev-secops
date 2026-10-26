import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { AuthUser } from '../guards/jwt-auth.guard';

/** Injects into the controller the user set by JwtAuthGuard. */
export const CurrentUser = createParamDecorator(
  (_data: unknown, context: ExecutionContext): AuthUser =>
    context.switchToHttp().getRequest().user,
);
