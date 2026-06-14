/**
 * Project Span — Account data-rights routes (GDPR/DPDP/App Store 5.1.1(v)).
 *
 *   POST   /v1/account/export  — assemble + return the full JSON archive of the
 *                                caller's PHI (MVP: inline; prod: presigned S3 URL).
 *   DELETE /v1/account         — irreversible cascade deletion of the caller.
 *
 * Both delegate to src/compliance/dataRights.ts and are audited.
 */

import type { FastifyInstance } from 'fastify';

import { assembleExport, deleteAccount } from '../compliance/dataRights.js';
import { audit, authPreHandler, unauthorized } from './middleware.js';

// eslint-disable-next-line @typescript-eslint/require-await
export default async function accountRoutes(app: FastifyInstance): Promise<void> {
  app.addHook('preHandler', authPreHandler);

  // POST /v1/account/export — DPDP access + GDPR Art. 20 portability.
  app.post('/account/export', async (req, reply) => {
    if (!req.userId) throw unauthorized();

    const archive = await assembleExport(req.userId);

    await audit('phi.export', 'users', req.userId, {
      req,
      // counts only — never PHI values in the audit meta.
      detail: { tables: Object.keys(archive.counts).length, counts: archive.counts },
    });

    // PROD: instead of returning the body inline, write `archive` (+ raw PDFs) to
    // s3://span-phi-in/u/{userId}/exports/{ts}.json with SSE-KMS, then respond with
    // { download_url: <presigned GET, short TTL> }.  Inline JSON is the MVP form.
    return reply
      .header('content-type', 'application/json')
      .header('content-disposition', 'attachment; filename="span-export.json"')
      .code(200)
      .send(archive);
  });

  // DELETE /v1/account — GDPR Art. 17 erasure + DPDP withdrawal + App Store 5.1.1(v).
  app.delete('/account', async (req, reply) => {
    if (!req.userId) throw unauthorized();
    const userId = req.userId;

    // Audit the REQUEST before deletion so the actor/intent is recorded even if
    // the cascade is interrupted (the pipeline is idempotent + resumable).
    await audit('phi.delete_requested', 'users', userId, { req });

    const result = await deleteAccount(userId);

    // Note: deleteAccount() writes its own append-only 'phi.delete' completion
    // audit row inside the deletion transaction (durable proof).

    // TODO(auth): also revoke the user's refresh-token family + call Apple's token
    // revocation endpoint (§9 "Apple token revoke") once the authorization_code
    // exchange is wired up.  refresh_tokens already cascade-deleted via the FK.

    return reply.code(200).send(result);
  });
}
