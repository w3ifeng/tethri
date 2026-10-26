import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { createHandler, type QuotaEntry } from '../src/index.ts';

function registry() {
  const db = new DatabaseSync(':memory:');
  const sql = {exec(query: string, ...args: (string|number)[]) {
    if (!args.length && query.includes(';')) { db.exec(query); return {toArray:()=>[]}; }
    const statement = db.prepare(query);
    if (statement.columns().length) return {toArray:()=>statement.all(...args)};
    statement.run(...args); return {toArray:()=>[]};
  }};
  db.exec('CREATE TABLE quotas (scope TEXT, period TEXT, count INTEGER, PRIMARY KEY(scope,period))');
  const quotas = {async reserve(entries: QuotaEntry[]) {
    db.exec('BEGIN IMMEDIATE');
    try {
      for (const entry of entries) {
        const row = sql.exec('SELECT count FROM quotas WHERE scope=? AND period=?',entry.scope,entry.period).toArray()[0] as {count:number}|undefined;
        if ((row?.count ?? 0) >= entry.limit) { db.exec('ROLLBACK'); return false; }
      }
      for (const entry of entries) sql.exec('INSERT INTO quotas VALUES (?,?,1) ON CONFLICT(scope,period) DO UPDATE SET count=count+1',entry.scope,entry.period);
      db.exec('COMMIT'); return true;
    } catch(e) { db.exec('ROLLBACK'); throw e; }
  }};
  const env = {GEMINI_API_KEY:'test-key', INSTALLATION_RPM:'5', PROJECT_RPM:'14'};
  const handler = createHandler(env,quotas);
  const send = (path:string,input:unknown,client = 'client-one') => handler(new Request('https://focus.test'+path,{method:'POST',headers:{'Content-Type':'application/json','X-Focus-Client':client},body:JSON.stringify(input)}));
  return {send,env,sql};
}
const request = () => ({requestId:crypto.randomUUID(),sessionId:crypto.randomUUID(),interventionId:null,message:'This is a lecture',recentConversation:[],label:'youtube.com',studyGoal:'Algebra',breakEligible:false,studyRemainingSeconds:900,maxBreakMinutes:5});
const originalFetch = globalThis.fetch;
test('invitation and admin routes are removed', async () => {
  const r=registry();
  for (const path of ['/internal/admin/invites','/internal/admin/revoke','/v1/installations/redeem']) assert.equal((await r.send(path,{})).status,404);
});
test('provider retries count and quotas hold across simultaneous requests', async () => {
  const r=registry(); r.env.INSTALLATION_RPM='2';  let calls=0;
  globalThis.fetch=async()=>{ calls++; return new Response('unavailable',{status:503}); };
  try {
    const first=await r.send('/v1/companion/interpret',request()); assert.equal(first.status,503); assert.equal(calls,2);
    const denied=await Promise.all(Array.from({length:4},()=>r.send('/v1/companion/interpret',request())));
    assert.ok(denied.every(x=>x.status===429)); assert.equal(calls,2);
  } finally { globalThis.fetch=originalFetch; }
});
test('project quota is shared by all clients', async () => {
  const r=registry(); r.env.PROJECT_RPM='1'; const one='client-one'; const two='client-two'; let calls=0;
  globalThis.fetch=async()=>{ calls++; return Response.json({candidates:[{content:{parts:[{text:JSON.stringify({intent:'chat',requestedBreakMinutes:null,reply:'Keep going.'})}]}}]}); };
  try {
    assert.equal((await r.send('/v1/companion/interpret',request(),one)).status,200);
    assert.equal((await r.send('/v1/companion/interpret',request(),two)).status,429); assert.equal(calls,1);
  } finally { globalThis.fetch=originalFetch; }
});
test('invalid model responses fail safely; no prompts or browsing metadata in logs', async () => {
  const r=registry();  const logs:string[]=[]; const originalLog=console.log;
  console.log=(value)=>logs.push(String(value));
  globalThis.fetch=async()=>Response.json({candidates:[{content:{parts:[{text:'{"intent":"execute","reply":"injected"}'}]}}]});
  try {
    const result=await r.send('/v1/companion/interpret',request()); assert.equal(result.status,503);
    assert.ok(logs.length>0); for(const log of logs) { assert.ok(!log.includes('youtube')); assert.ok(!log.includes('lecture')); assert.ok(!log.includes('client-one')); }
  } finally { globalThis.fetch=originalFetch; console.log=originalLog; }
});
test('public chat works without credentials and echoes the model contract', async () => {
  const r=registry(); const input=request();
  globalThis.fetch=async()=>Response.json({candidates:[{content:{parts:[{text:JSON.stringify({intent:'study_exception',requestedBreakMinutes:null,reply:'Let’s focus.'})}]}}],usageMetadata:{totalTokenCount:45}});
  try { const result=await r.send('/v1/companion/interpret',input); const value=await result.json() as any; assert.equal(result.status,200); assert.equal(value.requestId,input.requestId); assert.equal(value.intent,'study_exception'); assert.equal(value.message,undefined); }
  finally {globalThis.fetch=originalFetch;}
});

test('database failures fail closed without calling Gemini', async () => {
  let called=false;
  const handler=createHandler({GEMINI_API_KEY:'test-key'}, {async reserve(){throw new Error('private database details');}});
  globalThis.fetch=async()=>{called=true;return new Response();};
  try {
    const result=await handler(new Request('https://focus.test/v1/companion/interpret',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(request())}));
    assert.equal(result.status,503); assert.equal(called,false);
    assert.deepEqual(await result.json(),{error:'service_unavailable'});
  } finally {globalThis.fetch=originalFetch;}
});
test('Gemini receives current context and history and its conversational reply is preserved', async () => {
  const r = registry();
  const input = {...request(), message:'Why do you keep asking about my work?', label:'github.com (Productive)',
    recentConversation:[{role:'assistant',text:'Session ended. We can keep chatting.'}],
    context:{sessionPhase:'idle',breakRemainingSeconds:0,interventionLabel:null,studyAccess:'none'}};
  const reply = 'You are right; I only need to keep you on task, not quiz you about your work.';
  globalThis.fetch = async (_url, options) => {
    const provider = JSON.parse(options!.body as string);
    assert.deepEqual(JSON.parse(provider.contents[0].parts[0].text), input);
    assert.ok(provider.systemInstruction.parts[0].text.includes('Answer the user\'s latest message directly'));
    assert.ok(provider.systemInstruction.parts[0].text.includes('Do not turn this into a discussion of their work'));
    assert.ok(provider.systemInstruction.parts[0].text.includes('Stop there; do not pivot into their work'));
    const policy = JSON.parse(provider.systemInstruction.parts[1].text.split(': ').slice(1).join(': '));
    assert.equal(policy.role, 'focus_accountability_companion');
    assert.equal(policy.breakState, 'no_session');
    assert.equal(policy.focusMinutesUntilBreak, null);
    return Response.json({candidates:[{content:{parts:[{text:JSON.stringify({intent:'chat',requestedBreakMinutes:null,reply})}]}}]});
  };
  try {
    const result = await r.send('/v1/companion/interpret', input);
    assert.equal(result.status, 200);
    assert.equal((await result.json() as any).reply, reply);
  } finally { globalThis.fetch = originalFetch; }
});
test('an early break request sends explicit unearned-break instructions to Gemini', async () => {
  const r = registry();
  const input = {...request(),message:'I want a break now',
    recentConversation:[{role:'assistant',text:'Go ahead and take a break whenever you want.'}],
    context:{sessionPhase:'focus',breakRemainingSeconds:0,interventionLabel:null,studyAccess:'none'}};
  const reply = 'There are 15 minutes left before your break is available. Stick with your session until then.';
  globalThis.fetch = async (_url, options) => {
    const provider = JSON.parse(options!.body as string);
    const instructions = provider.systemInstruction.parts.map((part: {text:string}) => part.text).join('\n');
    assert.ok(instructions.includes('do not recommend, approve, or encourage taking that break now'));
    assert.ok(instructions.includes('"breakState":"not_earned"'));
    assert.ok(instructions.includes('"focusMinutesUntilBreak":15'));
    assert.ok(!instructions.includes(input.recentConversation[0].text));
    return Response.json({candidates:[{content:{parts:[{text:JSON.stringify({intent:'break_request',requestedBreakMinutes:null,reply})}]}}]});
  };
  try {
    const result = await r.send('/v1/companion/interpret', input);
    assert.equal(result.status, 200);
    const value = await result.json() as any;
    assert.equal(value.intent, 'break_request');
    assert.equal(value.reply, reply);
  } finally { globalThis.fetch = originalFetch; }
});
