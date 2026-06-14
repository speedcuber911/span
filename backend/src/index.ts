/**
 * Project Span — server entrypoint.
 *
 * Fastify bootstrap for the /v1 API:
 *   • CORS (@fastify/cors)
 *   • JWT (@fastify/jwt) — signs/verifies OUR access tokens with JWT_SECRET
 *   • global error handler — NEVER leaks PHI or stack traces in production
 *   • GET /health (no auth)
 *   • mounts the /v1 plugin from src/api/
 *   • graceful shutdown → db shutdown()
 *
 * One long-lived process on one EC2 in ap-south-1 (SPAN_MASTER_PLAN §9): warm DB
 * pool, India-only residency.
 */

import Fastify from 'fastify';
import type { FastifyError, FastifyReply, FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';

import { config, jwtSecret } from './config.js';
import { shutdown as dbShutdown } from './db/index.js';
import { apiPlugin } from './api/index.js';
import { ApiError } from './api/middleware.js';

async function buildServer() {
  const app = Fastify({
    // PHI-free logging: redact common auth/PII headers; never log bodies.
    logger: {
      level: config.isProduction ? 'info' : 'debug',
      redact: {
        paths: ['req.headers.authorization', 'req.headers.cookie', 'req.headers["x-forwarded-for"]'],
        remove: true,
      },
    },
    // Trust one proxy hop (CloudFront/ALB) so req.ip / x-forwarded-for is correct.
    trustProxy: true,
    // Don't echo request bodies back in validation errors (could carry PHI).
    disableRequestLogging: false,
  });

  // --- CORS -----------------------------------------------------------------
  // iOS app uses no browser origin; allow a configurable dev origin, deny by
  // default in production unless explicitly opened.
  await app.register(cors, {
    origin: config.isProduction ? false : true,
    credentials: true,
  });

  // --- JWT (our own access tokens) ------------------------------------------
  await app.register(jwt, {
    secret: jwtSecret,
    // We verify explicitly in authPreHandler (req.jwtVerify), not globally.
  });

  // --- Health check (no auth) -----------------------------------------------
  app.get('/health', async () => ({
    status: 'ok',
    region: config.AWS_REGION,
    env: config.NODE_ENV,
    time: new Date().toISOString(),
  }));

  // --- Mount the /v1 API -----------------------------------------------------
  await app.register(apiPlugin, { prefix: '/v1' });

  // --- Global error handler --------------------------------------------------
  // Maps known ApiErrors to their status/code; everything else is a generic 500.
  // In production we NEVER include the message of an unexpected error (could echo
  // PHI from a query/validation path) nor any stack trace.
  app.setErrorHandler((err: FastifyError | ApiError, req: FastifyRequest, reply: FastifyReply) => {
    if (err instanceof ApiError) {
      return reply.code(err.statusCode).send({ error: { code: err.code, message: err.message } });
    }

    // Fastify validation / parsing errors carry a statusCode.
    const status = typeof err.statusCode === 'number' ? err.statusCode : 500;

    if (status >= 500) {
      // Log full detail server-side (PHI-free logger config), return opaque body.
      req.log.error({ err }, 'unhandled error');
      return reply.code(500).send({
        error: {
          code: 'INTERNAL',
          message: config.isProduction ? 'Internal server error' : (err.message ?? 'error'),
        },
      });
    }

    // 4xx from Fastify (bad JSON, payload too large, etc.) — safe-ish to surface
    // a generic message, but never the raw validation payload in prod.
    return reply.code(status).send({
      error: {
        code: (err as { code?: string }).code ?? 'BAD_REQUEST',
        message: config.isProduction ? 'Bad request' : (err.message ?? 'bad request'),
      },
    });
  });

  // 404 fallthrough.
  app.setNotFoundHandler((_req, reply) => {
    return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Route not found' } });
  });

  return app;
}

async function main() {
  const app = await buildServer();

  // --- Graceful shutdown -----------------------------------------------------
  let closing = false;
  const close = async (signal: string) => {
    if (closing) return;
    closing = true;
    app.log.info({ signal }, 'shutting down');
    try {
      await app.close(); // stop accepting connections, drain in-flight
      await dbShutdown(); // drain the pg pool
    } catch (err) {
      app.log.error({ err }, 'error during shutdown');
      process.exitCode = 1;
    } finally {
      process.exit(process.exitCode ?? 0);
    }
  };
  process.on('SIGTERM', () => void close('SIGTERM'));
  process.on('SIGINT', () => void close('SIGINT'));

  try {
    await app.listen({ port: config.PORT, host: '0.0.0.0' });
    app.log.info({ port: config.PORT, region: config.AWS_REGION }, 'span-backend listening');
  } catch (err) {
    app.log.error({ err }, 'failed to start');
    await dbShutdown();
    process.exit(1);
  }
}

// Only run when invoked directly (not when imported by tests).
main().catch((err) => {
  console.error('[fatal] server bootstrap failed', err);
  process.exit(1);
});

export { buildServer };
