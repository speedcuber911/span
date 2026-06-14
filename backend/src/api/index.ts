/**
 * Project Span — /v1 API plugin.
 *
 * Registers every route this layer owns under the /v1 prefix, plus 501 stubs for
 * the surfaces other agents own (ingestion, voice, analysis read-models).  The
 * server entrypoint (src/index.ts) mounts this once.
 */

import type { FastifyInstance, FastifyPluginAsync } from 'fastify';

import authRoutes from './auth.js';
import consentRoutes from './consent.js';
import accountRoutes from './account.js';
import profileRoutes from './profile.js';
import { ApiError, authPreHandler } from './middleware.js';

/**
 * Stub for endpoints owned by OTHER agents.  Returns 501 so the contract surface
 * is visible (and auth-gated) without claiming functionality this layer doesn't own.
 */
function notImplemented(app: FastifyInstance, method: 'get' | 'post', path: string, owner: string) {
  app.route({
    method: method.toUpperCase() as 'GET' | 'POST',
    url: path,
    preHandler: authPreHandler,
    handler: async () => {
      throw new ApiError(501, 'NOT_IMPLEMENTED', `${path} is owned by the ${owner} layer (not yet wired)`);
    },
  });
}

export const apiPlugin: FastifyPluginAsync = async (app: FastifyInstance) => {
  // --- Owned by THIS layer (auth / consent / compliance / profile) ----------
  await app.register(authRoutes);
  await app.register(consentRoutes);
  await app.register(accountRoutes);
  await app.register(profileRoutes);

  // --- Stubs for other agents' surfaces (SPAN_MASTER_PLAN §4/§6/§8) ----------
  // Ingestion layer (src/ingestion):
  notImplemented(app, 'post', '/ingestion/intents', 'ingestion');
  notImplemented(app, 'post', '/ingestion/:jobId/complete', 'ingestion');
  notImplemented(app, 'get', '/ingestion/jobs', 'ingestion');

  // Analysis read-models (src/analysis materialized → read API):
  notImplemented(app, 'get', '/overview', 'analysis');
  notImplemented(app, 'get', '/systems/:key', 'analysis');
  notImplemented(app, 'get', '/parameters/:id', 'analysis');
  notImplemented(app, 'get', '/bioage', 'analysis');

  // Voice (src/voice):
  notImplemented(app, 'post', '/voice/sessions', 'voice');
};

export default apiPlugin;
