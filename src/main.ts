import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { loadSecretsFromVault } from './config/vault';

async function bootstrap() {
  // Secrets must be in process.env BEFORE AppModule is loaded, because
  // ConfigModule validates the environment as soon as it is imported.
  // That is why AppModule is imported here and not at the top of the file.
  await loadSecretsFromVault();
  const { AppModule } = await import('./app.module');

  const app = await NestFactory.create(AppModule);

  app.setGlobalPrefix('api');

  // Validates every incoming DTO:
  // - whitelist: strips properties the DTO does not declare
  // - forbidNonWhitelisted: and answers 400 if any are sent
  // This way nobody can sneak fields like "ownerId" into the body.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  await app.listen(process.env.PORT ?? 3000);
}

bootstrap();
