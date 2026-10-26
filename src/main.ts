import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.setGlobalPrefix('api');

  // Valida todos los DTOs de entrada:
  // - whitelist: descarta propiedades que el DTO no declara
  // - forbidNonWhitelisted: y además responde 400 si llegan
  // Así nadie puede colar campos como "ownerId" en el body.
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
