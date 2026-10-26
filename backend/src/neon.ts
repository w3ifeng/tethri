import { neon } from '@neondatabase/serverless';
import { createHandler, type QuotaStore } from './index.ts';

let handler: ((request: Request) => Promise<Response>) | undefined;
export default async function fetch(request: Request): Promise<Response> {
  if (!process.env.DATABASE_URL) return Response.json({error:'database_unconfigured'},{status:503});
  if (!handler) {
    const sql = neon(process.env.DATABASE_URL);
    const quotas: QuotaStore = {
      async reserve(entries, signal) {
        const rows = await sql.query('SELECT little_focus.reserve_quota($1::jsonb) AS allowed', [JSON.stringify(entries)], {fetchOptions:{signal}});
        return rows[0]?.allowed === true;
      }
    };
    handler = createHandler({
      GEMINI_API_KEY: process.env.GEMINI_API_KEY ?? '', GEMINI_MODEL: process.env.GEMINI_MODEL,
      PROJECT_RPM: process.env.PROJECT_RPM, PROJECT_RPD: process.env.PROJECT_RPD,
      INSTALLATION_RPM: process.env.INSTALLATION_RPM, INSTALLATION_RPD: process.env.INSTALLATION_RPD
    }, quotas);
  }
  return handler(request);
}
