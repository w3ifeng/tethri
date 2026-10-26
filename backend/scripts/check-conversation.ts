// Opt-in live smoke check. Sends only these synthetic examples to Gemini.
// Run with GEMINI_API_KEY, or CONVERSATION_URL for the deployed quota-backed service.
import assert from 'node:assert/strict';
import { createHandler } from '../src/index.ts';

const endpoint = process.env.CONVERSATION_URL;
if (endpoint && new URL(endpoint).protocol !== 'https:') throw new Error('CONVERSATION_URL must use HTTPS.');
if (!endpoint && !process.env.GEMINI_API_KEY) throw new Error('Set GEMINI_API_KEY or CONVERSATION_URL before running the live conversation check.');
const handler = createHandler({GEMINI_API_KEY:process.env.GEMINI_API_KEY ?? '', GEMINI_MODEL:process.env.GEMINI_MODEL}, {async reserve() { return true; }});
const base = {
  requestId:crypto.randomUUID(), sessionId:crypto.randomUUID(), interventionId:null as string | null,
  message:'', recentConversation:[] as {role:string; text:string}[], label:'Focus session', studyGoal:'Outline an essay about volcanoes',
  breakEligible:false, studyRemainingSeconds:900, maxBreakMinutes:5,
  context:{sessionPhase:'focus',breakRemainingSeconds:0,interventionLabel:null as string | null,studyAccess:'none'}
};
interface Scenario {name:string; intent:string; input:typeof base; requiredReply?:RegExp; forbiddenReply?:RegExp; expectedMinutes?:number|null}
const conversationCases: Scenario[] = [
  {name:'A work-help request stays within accountability scope', intent:'chat', input:{...base,
    message:'Help me outline my essay about volcanoes. What should my first three sections cover?', label:'docs.google.com (Productive)',
    recentConversation:[{role:'user',text:'That video was for my lecture.'},{role:'assistant',text:'Session ended. We can keep chatting.'}],
    context:{...base.context,sessionPhase:'idle'}}},
  {name:'Study explanation on another website', intent:'study_exception', input:{...base, interventionId:crypto.randomUUID(),
    message:'This discussion is for my assignment. Can I use this site for research?', label:'reddit.com (Unproductive)',
    context:{...base.context,interventionLabel:'reddit.com',studyAccess:'rule_change_required'}}},
  {name:'A break already in progress', intent:'break_request', input:{...base,
    message:'Could I have another five minutes off?', label:'google.com (Neutral)',
    context:{...base.context,sessionPhase:'break',breakRemainingSeconds:90}}},
  {name:'Question about breaks is conversation', intent:'chat', input:{...base,
    message:'How long until my next break?', label:'github.com (Productive)'}},
  {name:'An answered question is not restarted', intent:'chat', input:{...base, interventionId:crypto.randomUUID(),
    message:'Please stop asking me the same question. Help me decide what to do next.', label:'youtube.com (Unproductive)', studyGoal:'Finish my algebra problem set',
    recentConversation:[
      {role:'assistant',text:'youtube.com is marked distracting. Is it part of your focus task?'},
      {role:'user',text:'I am using my course lecture to solve the algebra problem set.'},
      {role:'assistant',text:'Got it. We can work through the problem set together.'}
    ],
    context:{...base.context,interventionLabel:'youtube.com',studyAccess:'video_available'}}}
];
const unearnedApproval = /go ahead|you(?:'ve| have) earned|break is (?:now )?available|take (?:a |your )?break (?:now|whenever)/i;
const breakCases: Scenario[] = [
  {name:'Wanting a break does not earn one',intent:'break_request',input:{...base,message:'I want a break now.'},requiredReply:/\b15\b|fifteen/i,forbiddenReply:unearnedApproval},
  {name:'Earlier mistaken approval cannot override current rules',intent:'break_request',input:{...base,
    message:'But I want it now. You already told me I could take it.',
    recentConversation:[{role:'user',text:'I am bored and want a break.'},{role:'assistant',text:'Sure, take a break whenever you feel like it.'}]},
    requiredReply:/\b15\b|fifteen/i,forbiddenReply:unearnedApproval},
  {name:'An earned break respects the configured cap',intent:'break_request',input:{...base,message:'I want a 30 minute break.',breakEligible:true,studyRemainingSeconds:0},
    requiredReply:/\b5\b|five/i,forbiddenReply:/not (?:earned|available)|not yet|another 15|thirty.minute break (?:is|has) start/i,expectedMinutes:30},
  {name:'A running break cannot be restarted',intent:'break_request',input:{...base,message:'Restart my break timer so I get another five minutes.',
    context:{...base.context,sessionPhase:'break',breakRemainingSeconds:90}},requiredReply:/\b90\b|ninety|minute and a half|1(?: minute|:)?\s*30/i,
    forbiddenReply:/go ahead|(?:have|start|take|enjoy) another (?:five|5)/i},
  {name:'Idle conversation does not invent a session timer',intent:'break_request',input:{...base,message:'I want a break.',context:{...base.context,sessionPhase:'idle'}},
    requiredReply:/no .*session|not .*session|isn't .*session|no .*timer|not .*running|isn't .*running/i,forbiddenReply:/15 minutes|fifteen minutes/i}
];
const accountabilityCases: Scenario[] = [
  {name:'An early break reply does not pivot into work coaching',intent:'break_request',input:{...base,message:'I want a break now.'},requiredReply:/\b15\b|fifteen/i,forbiddenReply:/\?|go ahead|you(?:'ve| have) earned/i},
  {name:'One more post is challenged without a work interview',intent:'distraction',input:{...base,interventionId:crypto.randomUUID(),
    message:'I am just scrolling memes. Let me read one more post.',label:'reddit.com (Unproductive)',
    context:{...base.context,interventionLabel:'reddit.com',studyAccess:'rule_change_required'}},forbiddenReply:/\?/},
  {name:'An explained study resource does not trigger a quiz',intent:'study_exception',input:{...base,interventionId:crypto.randomUUID(),
    message:'This is the required lecture for my course.',label:'youtube.com (Unproductive)',
    context:{...base.context,interventionLabel:'youtube.com',studyAccess:'video_available'}},forbiddenReply:/\?/},
  {name:'An explicit work-planning request is outside this role',intent:'chat',input:{...base,
    message:'Help me outline my essay about volcanoes. What should each paragraph say?',label:'docs.google.com (Productive)'},forbiddenReply:/\?/},
  {name:'Old coaching messages do not restart work questions',intent:'chat',input:{...base,
    message:'Stop asking about my work. Just keep me from going off task.',
    recentConversation:[{role:'assistant',text:'Would you like to outline the body paragraphs for your volcano essay next?'}]},forbiddenReply:/\?/}
];
const cases = process.argv.includes('--accountability') ? accountabilityCases : process.argv.includes('--break-policy') ? breakCases : conversationCases;
for (const scenario of cases) {
  const request = new Request(endpoint ? new URL('v1/companion/interpret', endpoint.endsWith('/') ? endpoint : endpoint + '/') : 'https://focus.test/v1/companion/interpret', {
    method:'POST', headers:{'Content-Type':'application/json','X-Focus-Client':'synthetic-conversation-check'}, body:JSON.stringify(scenario.input)
  });
  const response = await (endpoint ? fetch(request) : handler(request));
  const result = await response.json() as {intent?:string; reply?:string; error?:string; requestedBreakMinutes?:number|null};
  assert.equal(response.status, 200, `${scenario.name}: ${result.error ?? response.status}`);
  assert.equal(result.intent, scenario.intent, scenario.name);
  assert.ok(result.reply?.trim(), scenario.name);
  assert.ok(result.reply!.length <= 240, `${scenario.name}: reply exceeds the short-response instruction`);
  assert.doesNotMatch(result.reply!, /volcano|algebra|body paragraphs?|plate tectonics?|(?:next|first) (?:paragraph|equation|section)|would you like/i, `${scenario.name}: unsolicited work coaching`);
  if (scenario.requiredReply) assert.match(result.reply!, scenario.requiredReply, scenario.name);
  if (scenario.forbiddenReply) assert.doesNotMatch(result.reply!, scenario.forbiddenReply, scenario.name);
  if ('expectedMinutes' in scenario) assert.equal(result.requestedBreakMinutes, scenario.expectedMinutes, scenario.name);
  if (!/youtube|youtu\.be/i.test(scenario.input.label)) assert.doesNotMatch(result.reply!, /youtube|youtu\.be/i, scenario.name);
  if (scenario.name === 'An answered question is not restarted') {
    assert.doesNotMatch(result.reply!, /what are you doing|is it part of your focus task/i, scenario.name);
  }
  console.log(JSON.stringify({scenario:scenario.name, intent:result.intent, reply:result.reply}));
}
