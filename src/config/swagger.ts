import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

/**
 * Publishes the OpenAPI description of the API:
 *   /api/docs        interactive UI
 *   /api/docs-json   machine-readable spec (what OWASP ZAP reads)
 *
 * Only enabled when SWAGGER_ENABLED=true (local and test environments).
 * In production it would hand attackers a map of every endpoint.
 */
export function setupSwagger(app: INestApplication): void {
  const config = new DocumentBuilder()
    .setTitle('dev-secops notes API')
    .setVersion('1.0')
    .addBearerAuth()
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api/docs', app, document, {
    jsonDocumentUrl: 'api/docs-json',
  });
}
