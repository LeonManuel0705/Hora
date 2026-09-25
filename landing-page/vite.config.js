// SPDX-FileCopyrightText: 2026 Leon Manuel Töpper
// SPDX-License-Identifier: AGPL-3.0-only

import { defineConfig, loadEnv } from 'vite';
import { fileURLToPath, URL } from 'node:url';
import { viteStaticCopy } from 'vite-plugin-static-copy';
import { buildErrorOverlayPlugin } from './integrations/build-error-overlay.js';
import { runtimeErrorCapturePlugin } from './integrations/runtime-error-capture.js';
import { errorLoggerPlugin } from './integrations/error-logger.js';
import { contentResolver } from './integrations/content-resolver.js';
import { htmlValidator } from './integrations/html-validator.js';
import { metaInjector } from './integrations/meta-injector.js';
import { applyBrand, brandPlaceholder } from './integrations/brand-placeholder.js';
import { jsSyntaxValidator } from './integrations/js-syntax-validator.js';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');

  return {
    root: fileURLToPath(new URL('src', import.meta.url)),
    publicDir: fileURLToPath(new URL('public', import.meta.url)),
    plugins: [
      jsSyntaxValidator(),
      contentResolver(),
      brandPlaceholder(),
      mode === 'development' && htmlValidator(),
      metaInjector({ siteUrl: env.VITE_SITE_URL }),
      viteStaticCopy({
        targets: [
          {
            src: 'content/*.json',
            dest: 'content',
            transform: applyBrand,
          },
        ],
      }),
      runtimeErrorCapturePlugin({
        isDev: mode === 'development',
      }),
      mode === 'development' && buildErrorOverlayPlugin(),
      mode === 'development' && errorLoggerPlugin(),
    ],
    server: {
      port: 4321,
      open: false,
    },
    build: {
      outDir: fileURLToPath(new URL('dist', import.meta.url)),
      emptyOutDir: true,
      rollupOptions: {
        input: {
          main: fileURLToPath(new URL('src/index.html', import.meta.url)),
          404: fileURLToPath(new URL('src/404.html', import.meta.url)),
        },
      },
    },
  };
});
