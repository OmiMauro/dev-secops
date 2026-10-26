import swc from 'unplugin-swc';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.spec.ts'],
    // Mocks are reset before every test, so no test sees calls or return
    // values configured by a previous one.
    mockReset: true,
  },
  plugins: [
    // Vitest compiles TypeScript with esbuild, which does not emit
    // decorator metadata. NestJS dependency injection needs it, so the
    // code is compiled with SWC instead, the way `nest build` would.
    swc.vite({ module: { type: 'es6' } }),
  ],
});
