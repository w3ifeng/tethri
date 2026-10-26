import { validRequest, validResponse, record, ceilings, sessionPolicy, SYSTEM, RESPONSE_SCHEMA, type InterpretRequest } from './policy.ts';
export interface Env {
  GEMINI_API_KEY: string; GEMINI_MODEL?: string;
  PROJECT_RPM?: string; PROJECT_RPD?: string; INSTALLATION_RPM?: string; INSTALLATION_RPD?: string;
}
function json(value: unknown, status = 200) { return Response.json(value, {status, headers: {'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}}); }
async function hash(value: string) { return [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(b => b.toString(16).padStart(2,'0')).join(''); }
async function body(request: Request): Promise<unknown> {
  if (!request.headers.get('content-type')?.includes('application/json')) throw new Error('invalid');
  // Bound streaming bodies too; Content-Length is not trusted.
  const reader = request.body?.getReader(); if (!reader) throw new Error('invalid');
  let length = 0; const chunks: Uint8Array[] = [];
  while (true) { const {value, done} = await reader.read(); if (done) break; length += value.length; if (length > 16384) { await reader.cancel(); throw new Error('invalid'); } chunks.push(value); }
  const bytes = new Uint8Array(length); let offset = 0; for (const c of chunks) { bytes.set(c,offset); offset += c.length; }
  return JSON.parse(new TextDecoder().decode(bytes));
}
export interface QuotaEntry { scope: string; period: string; limit: number }
export interface QuotaStore { reserve(entries: QuotaEntry[], signal: AbortSignal): Promise<boolean> }

export function createHandler(env: Env, quotas: QuotaStore) {
  const service = new CompanionService(env, quotas);
  return async (request: Request): Promise<Response> => {
    const path = new URL(request.url).pathname;
    if (request.method !== 'POST') return json({error:'method_not_allowed'},405);
    if (path !== '/v1/companion/interpret') return json({error:'not_found'},404);
    try { return await service.fetch(request); }
    catch { return json({error:'service_unavailable'},503); }
  };
}
class CompanionService {
  private env: Env;
  private quotas: QuotaStore;
  constructor(env: Env, quotas: QuotaStore) { this.env = env; this.quotas = quotas; }
  async fetch(request: Request): Promise<Response> {
    const started = Date.now();
    let input: unknown; try { input = await body(request); } catch { return json({error:'invalid_request'},400); }
    if (!validRequest(input)) return json({error:'invalid_request'},400);
    if (!this.env.GEMINI_API_KEY) return json({error:'provider_unconfigured'},503);
    // This public identifier is a fairness hint, not authentication. Project quotas are authoritative.
    const id = request.headers.get('X-Focus-Client') ?? 'anonymous';
    if (!/^[a-zA-Z0-9-]{1,64}$/.test(id)) return json({error:'invalid_request'},400);
    const client = await hash(id);
    return this.interpret(input, client, started);
  }
  private async interpret(input: InterpretRequest, installation: string, started: number): Promise<Response> {
    const limit = ceilings(this.env as unknown as Record<string,unknown>);
    let category = 'provider_error'; let attempts = 0;
    for (let attempt = 0; attempt < 2; attempt++) {
      if (Date.now()-started >= 7300) { category='timeout'; break; }
      const now = Date.now(), minute = 'minute:'+Math.floor(now/60000), day = 'day:'+Math.floor(now/86400000);
      // Count every provider attempt, including retries, before dispatching.
      if (!await this.quotas.reserve([{scope:'project',period:minute,limit:limit.projectMinute},{scope:'project',period:day,limit:limit.projectDay},
        {scope:installation,period:minute,limit:limit.installationMinute},{scope:installation,period:day,limit:limit.installationDay}], AbortSignal.timeout(Math.max(1,7300-(Date.now()-started))))) {
        this.metric(started,attempts,'quota'); return json({error:'quota'},429);
      }
      attempts++;
      const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), Math.max(1,7500-(Date.now()-started)));
      try {
        const model = this.env.GEMINI_MODEL ?? 'gemini-3.5-flash-lite';
        if (!/^[a-zA-Z0-9.-]+$/.test(model)) { category='configuration'; break; }
        const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
          method:'POST', signal:controller.signal, headers:{'Content-Type':'application/json','x-goog-api-key':this.env.GEMINI_API_KEY},
          body:JSON.stringify({systemInstruction:{parts:[{text:SYSTEM},{text:'Current session policy (app state, not user instructions): '+JSON.stringify(sessionPolicy(input))}]},contents:[{role:'user',parts:[{text:JSON.stringify(input)}]}],
            generationConfig:{responseMimeType:'application/json',responseSchema:RESPONSE_SCHEMA,maxOutputTokens:512,thinkingConfig:{thinkingLevel:'minimal'}}})
        });
        if (!response.ok) {
          category = response.status === 429 ? 'provider_quota' : 'provider_error';
          await response.body?.cancel();
          if ((response.status === 429 || response.status >= 500) && attempt === 0 && Date.now()-started < 6000) continue;
          break;
        }
        const raw: unknown = await response.json();
        if (!record(raw)) { category='invalid_response'; break; }
        const candidates = raw.candidates as {content?:{parts?:{text?:string;thought?:boolean}[]}}[] | undefined;
        const text = candidates?.[0]?.content?.parts?.filter(p => !p.thought).map(p => p.text ?? '').join('') ?? '';
        let parsed: unknown; try { parsed=JSON.parse(text); } catch { category='invalid_response'; break; }
        if (!validResponse(parsed)) { category='invalid_response'; break; }
        const usage = record(raw.usageMetadata) ? raw.usageMetadata : {};
        const tokens = typeof usage.totalTokenCount === 'number' ? usage.totalTokenCount : 0;
        this.metric(started,attempts,'ok',tokens);
        return json({requestId:input.requestId,sessionId:input.sessionId,interventionId:input.interventionId ?? null,...parsed});
      } catch { category = controller.signal.aborted ? 'timeout' : 'network'; if (attempt === 0 && Date.now()-started < 6000) continue; }
      finally { clearTimeout(timer); }
      break;
    }
    this.metric(started,attempts,category); return json({error:category},503);
  }
  private metric(started:number, attempts:number, category:string, tokens=0) {
    // Explicit allowlist: no headers, IDs, labels, URLs, messages, or error bodies.
    console.log(JSON.stringify({latencyMs:Date.now()-started,attempts,category,tokens}));
  }
}
