/**
 * What to ask the sage, and how to make sense of what comes back.
 *
 * The same person who reads palms and faces, in conversation. `PANDIT_VOICE`, `BOUNDARIES` and
 * `STYLE` are reused verbatim from `pandit.ts` — a user who reads their palm on Monday and talks
 * to Astro on Friday must not meet two different characters.
 *
 * `BOUNDARIES` matters more here than anywhere else in the app. A reading is asked one question,
 * by a screen. A chat can be asked anything, by a person: whether they will recover, whether they
 * should take the job, when they will marry, whether their child is safe. Every one of those is
 * covered by the block, and this is the surface where it will actually be tested.
 */

import { text } from "./gemini.ts";
import { Chart, describeChart } from "./jyotish.ts";
import { panditSystemPrompt } from "./pandit.ts";

/** The four pills on the opening screen, and what each one opens with. */
export const CHAT_TOPICS = [
  "love",
  "career",
  "future",
  "guidance",
] as const;

export type ChatTopic = typeof CHAT_TOPICS[number];

/** What the sage is still missing, so the app can raise the right control. */
export const ASK_FOR = ["none", "birth_time", "birth_place"] as const;
export type AskFor = typeof ASK_FOR[number];

// ---------------------------------------------------------------- the craft

const CHAT_CRAFT = `
YOU ARE IN CONVERSATION.

Someone has come to sit with you. They will ask about love, work, the season ahead, or something
troubling them that they may take a while to name. Answer as a jyotishi answers: from the chart
in front of you, in the register of someone who has done this for forty years and is in no hurry.

HOW A REPLY IS SHAPED.

Every reply is a small reading, not a chat message:

- A verdict: the answer itself, in one or two sentences, before anything else.
- A title with one emoji before it — "Your Love Reading", "The Season Ahead", "What Your Chart
  Says of Work". Name the subject, not the person.
- An opening paragraph that explains the verdict and cites the chart.
- Then up to three short labelled sections, each with its own emoji, its own heading of two or
  three words, and two sentences at most. These are where the practical part lives.

Do not greet them again in every reply. You greeted them once; now you are simply talking.

ANSWER FIRST. THIS IS THE MOST IMPORTANT INSTRUCTION HERE.

The "verdict" is the answer to what they actually asked, committed to plainly, before you have
explained anything. They asked who they were in a past birth: name who. They asked about the year
ahead in their work: say what it holds. They asked whether to trust someone: say what the chart
leans toward.

The "opening" then explains why — what in the chart, in what they have told you, or in their palm
or face reading brought you to it. Verdict, then reasons. Never reasons that wander toward a
verdict.

A verdict fails if it restates the question, if it describes what you are about to do ("let us
look at your chart"), or if it could sit unchanged on top of a reply to a different question. If
you find you cannot write one, you have not answered them yet — go back and answer.

WHEN THE QUESTION IS NOT ONE A CHART CAN SETTLE.

They will ask about past births, about whether they are cursed, about who they were, about when
love will come. A jyotishi does not deflect these and does not answer them with a shrug about the
soul being unknowable. You answer them the way the tradition answers them: from the nakshatra —
its symbol, its deity, its gana, its ruling graha — and from the Moon's rashi, which is what the
tradition reads a past birth from.

So: name the thing. A life spent near water. A keeper of records. Someone who tended others and
was not much thanked for it. A temperament carried over rather than a biography. Then show your
working — "your Chandra sits in Rohini, whose symbol is the cart and whose deity is Brahma, and
that is the mark of one who gathers and makes things grow."

Speaking in the tradition's own frame is not the same as claiming a fact about the world, and it is
what they came for. What does not change is everything under BOUNDARIES below: no dates, no ages,
no guarantees, no deterministic verbs, nothing touching health. Answer with the certainty of
someone reading a chart, not the certainty of someone reporting the news.

WHAT YOU ARE READING FROM.

The chart below is computed, not invented. It is the Moon's real position at the moment they were
born. Treat it as fact and build on it. You may also draw on anything they have told you before,
and on their palm or face reading if they have had one.

THE JYOTISH YOU KNOW.

The Moon's rashi is the sign that matters most — in this tradition "your sign" means the Moon's,
not the Sun's. The nakshatra beneath it is finer still, and is where the real character of a
reading comes from. Speak of grahas by their Indian names — Chandra, Surya, Mangal, Budh,
Guru, Shukra, Shani — glossing each once. Never invent a planetary position you were not given:
you have the Moon and the Sun, and nothing else. If you find yourself wanting Mangal's house to
make a point, make a different point.

ASKING FOR WHAT YOU LACK.

If something is marked UNKNOWN below, and knowing it would sharpen the reading, ask for it — but
only one thing, only when the conversation makes room for it, and always in your own voice. "At
what hour did you arrive?" not "Please provide your time of birth." Then read anyway, with what
you have. A reading held hostage to a missing field is not a reading.

Set "ask_for" to what you asked for, so the question can be made easy to answer. Set it to "none"
whenever you did not ask.

OFFERING SOMEWHERE TO GO NEXT.

End most replies with two to four short things they might ask next, in "options" — the words they
would say, in the first person, four or five words each: "What of my career?", "Tell me of
Shani". Not commands, not menu items. Leave it empty when the reply already asks them something.

WHAT TO REMEMBER.

When they tell you something true about their life — what they do, who they live with, what is
weighing on them, what they are hoping for — record it in "remember" so you have it next time.
A short snake_case key and a short value: {"key": "works_as", "value": "a schoolteacher in Pune"}.

Only what they actually said. Never a guess, never something you inferred from the chart, never
anything from the forbidden list below. If they said nothing new, return an empty array.
`.trim();

/**
 * The grounding rule, rewritten for a conversation.
 *
 * `GROUNDING` in `pandit.ts` is about a photograph and cannot be reused. The rule it enforces
 * can: name your evidence, or you are writing a horoscope column.
 */
const CHAT_GROUNDING = `
HOW TO GROUND A READING — this matters more than anything else here.

Every reply must rest on something specific, and say what it rests on:

- the chart — "your Chandra sits in Rohini, and Rohini does not give its trust quickly";
- something they told you, this conversation or a previous one — "you said the work tires you";
- their palm or face reading, if they have had one.

A reply that could have been sent to any stranger is a failed reply, however well written. If you
genuinely have nothing to ground a claim in, say less and ask more.

Never invent a fact about their life to cite. Citing something they did not say is worse than
citing nothing.
`.trim();

const CHAT_LENGTHS = `
LENGTH — write to these budgets and do not pad. This is a phone screen, and a wall of text is
closed unread.

- verdict: at most 25 words, one or two sentences. The answer, and nothing but the answer.
- title: 2-5 words. One emoji before it, in "title_emoji".
- opening: 40-70 words. This explains the verdict; the sections are the detail.
- Each section heading: 2-3 words. Each section body: at most 35 words.
- At most three sections. Two is often better than three.
- Each option: 3-6 words.
`.trim();

export const SYSTEM_PROMPT = panditSystemPrompt({
  craft: CHAT_CRAFT,
  grounding: CHAT_GROUNDING,
  lengths: CHAT_LENGTHS,
});

// ---------------------------------------------------------------- the contract

export const CHAT_SCHEMA = {
  type: "OBJECT",
  propertyOrdering: ["reply", "options", "remember", "ask_for"],
  required: ["reply"],
  properties: {
    reply: {
      type: "OBJECT",
      // `verdict` first, and this ordering is load-bearing rather than cosmetic. Structured
      // output is generated in order, so the model must commit to an answer before it writes a
      // word of justification — the same lever `pandit.ts` pulls to put observations ahead of the
      // prose that cites them. Reversed, the verdict would be a summary of reasoning already
      // written, which is exactly the hedging this field exists to end.
      propertyOrdering: ["verdict", "title_emoji", "title", "opening", "sections"],
      required: ["verdict", "title", "opening"],
      properties: {
        verdict: { type: "STRING" },
        title_emoji: { type: "STRING" },
        title: { type: "STRING" },
        opening: { type: "STRING" },
        sections: {
          type: "ARRAY",
          maxItems: 3,
          items: {
            type: "OBJECT",
            propertyOrdering: ["emoji", "heading", "body"],
            required: ["heading", "body"],
            properties: {
              emoji: { type: "STRING" },
              heading: { type: "STRING" },
              body: { type: "STRING" },
            },
          },
        },
      },
    },

    options: { type: "ARRAY", maxItems: 4, items: { type: "STRING" } },

    remember: {
      type: "ARRAY",
      maxItems: 5,
      items: {
        type: "OBJECT",
        propertyOrdering: ["key", "value"],
        required: ["key", "value"],
        properties: {
          key: { type: "STRING" },
          value: { type: "STRING" },
        },
      },
    },

    ask_for: { type: "STRING", enum: [...ASK_FOR] },
  },
};

// ---------------------------------------------------------------- the user prompt

export interface ChatContext {
  name?: string | null;
  age?: number | null;
  chart: Chart | null;

  /** What is already known, oldest first. */
  facts: Array<{ key: string; value: string }>;

  /** A sentence or two about their newest palm reading, if any. */
  palmSummary?: string | null;
  faceSummary?: string | null;

  /** True when this is the opening turn, so the sage greets rather than continues. */
  opening: boolean;
}

/**
 * Everything the sage should know before answering, and then the question.
 *
 * Assembled per turn rather than kept in the history, so a fact learned three messages ago is
 * present at full strength rather than buried where the model may not look. It also means
 * deleting a fact in Profile takes effect on the very next reply.
 */
export function buildUserPrompt(message: string, context: ChatContext): string {
  const blocks: string[] = [];

  const who = context.name?.trim()
    ? `You are speaking with ${context.name.trim()}${
      context.age ? `, who is ${context.age}` : ""
    }.`
    : "You do not know this person's name. Do not invent one or address them by name.";
  blocks.push(who);

  const chart = describeChart(context.chart);
  blocks.push(
    chart
      ? `THEIR CHART (computed, not invented — build on it):\n${chart}`
      : "THEIR CHART: unavailable, because their date of birth is not on file. Read from what " +
        "they tell you, and do not pretend to a chart you do not have.",
  );

  if (context.facts.length > 0) {
    blocks.push(
      "WHAT YOU ALREADY KNOW ABOUT THEM (from earlier conversations — use it, and do not ask " +
        "again for something already here):\n" +
        context.facts.map((fact) => `- ${fact.key}: ${fact.value}`).join("\n"),
    );
  } else {
    blocks.push(
      "You know nothing about their life yet beyond the chart. Let that shape how much you " +
        "claim.",
    );
  }

  const readings = [context.palmSummary, context.faceSummary].filter((s) => s);
  if (readings.length > 0) {
    blocks.push(`THEIR READINGS SO FAR:\n${readings.join("\n")}`);
  }

  if (context.opening) {
    blocks.push(
      "This is the first thing you have ever said to them. Greet them once, warmly and briefly, " +
        "by name if you have it — then answer.",
    );
  }

  blocks.push(`THEY SAY:\n${message}`);

  return blocks.join("\n\n");
}

// ---------------------------------------------------------------- normalising

export interface NormalisedSection {
  emoji: string;
  heading: string;
  body: string;
}

export interface NormalisedReply {
  /** The answer, before the reasoning. May be empty; see [normaliseChatReply]. */
  verdict: string;

  titleEmoji: string;
  title: string;
  opening: string;
  sections: NormalisedSection[];
  options: string[];
  remember: Array<{ key: string; value: string }>;
  askFor: AskFor;
}

/** A memory key has to be a short slug, or it is not a key at all. */
const KEY_PATTERN = /^[a-z][a-z0-9_]{1,39}$/;

/**
 * How many words a key may be made of.
 *
 * Slugifying is worth doing — the model writes "works as" often enough that recovering it beats
 * being strict — but slugifying alone turns "They work as a teacher" into a technically valid
 * key, and that defeats the entire point of the column. The key is a primary key: it is what
 * makes a fact *correct* itself next time rather than pile up beside a contradictory twin. A
 * whole sentence will never be produced identically twice, so it can never overwrite, and the
 * prompt slowly fills with near-duplicates.
 *
 * Three segments covers every real key — works_as, lives_in, worries_about, partner_name — and
 * excludes prose.
 */
const MAX_KEY_WORDS = 3;

/**
 * Turns whatever the model returned into something the app can render.
 *
 * Same contract as the reading normalisers: **never throws**. A reply that lost its sections is
 * still a reply worth showing, and a chat that errors because one field came back odd is worse
 * than one that shows a slightly thinner answer.
 *
 * Pure and exported, so all of it is testable without a network or a key.
 */
export function normaliseChatReply(raw: unknown): NormalisedReply | null {
  const root = (raw ?? {}) as Record<string, unknown>;
  const reply = (root.reply ?? {}) as Record<string, unknown>;

  const opening = text(reply.opening, 900);
  // The one thing a reply cannot do without. Everything else has a sensible absence.
  if (!opening) return null;

  const sections: NormalisedSection[] = [];
  for (const entry of Array.isArray(reply.sections) ? reply.sections : []) {
    const section = (entry ?? {}) as Record<string, unknown>;
    const heading = text(section.heading, 60);
    const body = text(section.body, 400);
    if (!heading || !body) continue;

    sections.push({ emoji: emoji(section.emoji), heading, body });
    if (sections.length === 3) break;
  }

  const options: string[] = [];
  for (const entry of Array.isArray(root.options) ? root.options : []) {
    const option = text(entry, 60);
    if (option && !options.includes(option)) options.push(option);
    if (options.length === 4) break;
  }

  const remember: Array<{ key: string; value: string }> = [];
  const seen = new Set<string>();
  for (const entry of Array.isArray(root.remember) ? root.remember : []) {
    const fact = (entry ?? {}) as Record<string, unknown>;
    const key = text(fact.key, 40).toLowerCase().replace(/\s+/g, "_");
    const value = text(fact.value, 200);

    // A key that is not a slug — or is a whole sentence wearing underscores — is not a key. See
    // MAX_KEY_WORDS for why the length check matters as much as the shape one.
    if (!KEY_PATTERN.test(key) || key.split("_").length > MAX_KEY_WORDS) continue;
    if (!value || seen.has(key)) continue;

    seen.add(key);
    remember.push({ key, value });
    if (remember.length === 5) break;
  }

  const askFor = ASK_FOR.includes(root.ask_for as AskFor)
    ? root.ask_for as AskFor
    : "none";

  return {
    // Required by the schema but optional here, deliberately. This function's contract is that it
    // never throws and degrades to less — `opening` stays the one field a reply cannot do
    // without, and a reply that lost its verdict is still worth showing exactly as replies looked
    // before this field existed. That also covers every row written before it did.
    verdict: text(reply.verdict, 200),
    titleEmoji: emoji(reply.title_emoji),
    title: text(reply.title, 80),
    opening,
    sections,
    options,
    remember,
    askFor,
  };
}

/**
 * One emoji, or nothing.
 *
 * Clamped by *code points*, not by `length`: most emoji are surrogate pairs, so a naive
 * `slice(0, 2)` cuts one in half and leaves a replacement character on the screen.
 */
function emoji(raw: unknown): string {
  const value = String(raw ?? "").trim();
  if (!value) return "";
  return [...value].slice(0, 2).join("");
}
