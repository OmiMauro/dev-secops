import { DataSource } from 'typeorm';

/**
 * Connection used by the TypeORM CLI (npm run migration:*).
 * The app itself connects through database.config.ts; both read the
 * same environment variables.
 */
export default new DataSource({
  type: 'postgres',
  host: process.env.DB_HOST,
  port: Number(process.env.DB_PORT),
  username: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  entities: [__dirname + '/../modules/**/entities/*.entity.{ts,js}'],
  migrations: [__dirname + '/../migrations/*.{ts,js}'],
});
