import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  blockedReply,
  CrisisLanguage,
  crisisLanguageFor,
  crisisReply,
  detectCrisis,
  fixedReplyBody,
  HELPLINES,
} from "../_shared/crisis.ts";
import { GeminiError } from "../_shared/gemini.ts";

/**
 * The crisis check runs before the model on every chat turn, so what it catches and what it
 * leaves alone is the whole of its behaviour.
 *
 * The first block is real: messages sent to Astro in the ten days to 24 Sep 2026, before this
 * existed. Each one was answered with a reading. Each one must now be caught.
 */

const REAL_MESSAGES: Array<[string, CrisisLanguage]> = [
  ["ನಿಖರವಾದ ಸಮಯ ಕೊಡಿ ನಾನು ಆತ್ಮಹತ್ಯೆ ಮಾಡಿಕೊಳ್ಳುವ ನಿರ್ಧಾರಕ್ಕೆ ಬಂದಿದ್ದೇನೆ", "kannada"],
  ["ನಾನು ಸಾಯುತ್ತೇನೆ", "kannada"],
  [
    "ನನಗೆ ಸದ್ಯ ಯಾವುದು ಕೆಲಸ ಇಲ್ಲ ಈಗ ನಾನು ಏನು ಮಾಡಬೇಕು ತಿಳಿಸಿ ಸಾಲದ ಹೊರೆಯಿಂದ ಸಾಯಿಬೇಕೆಂದು ತೀರ್ಮಾನ " +
    "ಮಾಡಿದ್ದೇನೆ",
    "kannada",
  ],
  ["mujhe wo nhi mila to m mar jaungi", "hinglish"],
  ["guruji ji mai mar jaunga usk bina usko bhut manta hu mai isiliye khona nahi chahta", "hinglish"],
  ["I want to die", "english"],
  ["to hamko jina nahi chahiye jab pyar hi nahi to jina kis kaam ka", "hinglish"],
  [
    "मैं 17 लाख का कर्ज से परेशान हूं कब तक मेरा समाधान होगा दिन रात नींद नहीं आ रहा है सिर्फ मन कर " +
    "रहा है खुदकुशी",
    "hindi",
  ],
];

Deno.test("every real crisis message from the week before is caught, in its own language", () => {
  for (const [message, language] of REAL_MESSAGES) {
    const match = detectCrisis(message);
    assert(match !== null, `missed: ${message}`);
    assertEquals(match.language, language, `wrong language for: ${message}`);
  }
});

Deno.test("each supported script has a first-person form that is caught", () => {
  const cases: Array<[string, CrisisLanguage]> = [
    ["मैं मर जाऊंगी उसके बिना", "hindi"],
    ["मला मरायचं आहे", "marathi"],
    ["எனக்கு சாக வேண்டும் போல் இருக்கிறது", "tamil"],
    ["నాకు చనిపోవాలని ఉంది", "telugu"],
    ["എനിക്ക് മരിക്കണം", "malayalam"],
    ["আমি মরে যেতে চাই", "bengali"],
    ["મારે મરી જવું છે", "gujarati"],
    ["i dont want to live anymore", "english"],
    ["khud ko khatam kar lungi", "hinglish"],
    ["jeene ka mann nahi karta", "hinglish"],
    ["main marna chahti hu", "hinglish"],
    ["mujhe marna hai", "hinglish"],
    ["मैं मरना चाहता हूं", "hindi"],
    ["I do not want to live", "english"],
  ];

  for (const [message, language] of cases) {
    assertEquals(detectCrisis(message)?.language, language, message);
  }
});

Deno.test("Roman letters inside a Devanagari message still get the Devanagari reply", () => {
  // A Hindi message that says "suicide" is a Hindi message.
  assertEquals(detectCrisis("मैं suicide कर लूंगा")?.language, "hindi");
});

Deno.test("the everyday words that look like the stems are left alone", () => {
  for (
    const message of [
      // ಸಾಯಂಕಾಲ is "evening": typed every time someone gives a birth time in Kannada.
      "ಸಾಯಂಕಾಲ 4:30",
      "ಸಾಯಂಕಾಲ ಸರಿ ಸುಮಾರು 5 ಗಂಟೆ ಇರಬಹುದು",
      // Someone else, in the third person — "when will they die".
      "ನಮ್ಮವರಿಗೆ ಹತ್ತಿ ತುಂಬಾ ತಲೆ ತಿಂತಾರೆ ಯಾವಾಗ ಸಾಯ್ತಾರೆ",
      // Someone who has died, not someone who wants to.
      "mere papa mar gaye pichle saal",
      "wo mar jayega kya",
      "meri umar kitni hai",
      "kaam khatam kar lunga phir baat karenge",
      "main apni jaan se pyaar karta hu",
      "problem mein fasi hui hu",
      // From the fourteen-day scan: a breakup, a curse at someone else, and a typo for
      // "maanna" (accept) — none of them about wanting to die.
      "my girlfriend breakup with me and she don't want to live with me",
      "tum mar jao yeh sab bhi",
      "to kya uska yah shart mujhe marna chahie ki nahin",
      "Meri shaadi kab hogi?",
      "मेरा नया जॉब कब लगेगा",
      "Tell me more about my ಕುಜ ರೇಖೆ and what it means for me.",
      "",
      "   ",
    ]
  ) {
    assertEquals(detectCrisis(message), null, `fired on: ${message}`);
  }
});

Deno.test("only the first 2000 characters are scanned, like the message itself", () => {
  assertEquals(detectCrisis(`${"a ".repeat(1500)} I want to die`), null);
  assert(detectCrisis(`I want to die ${"a ".repeat(1500)}`) !== null);
});

// ---------------------------------------------------------------- the replies

const LANGUAGES: CrisisLanguage[] = [
  "english",
  "hinglish",
  "hindi",
  "marathi",
  "kannada",
  "tamil",
  "telugu",
  "malayalam",
  "bengali",
  "gujarati",
];

Deno.test("every reply carries all three numbers, in every language", () => {
  for (const language of LANGUAGES) {
    const text = crisisReply(language).join(" ");
    for (const { number } of HELPLINES) {
      assert(text.includes(number), `${language} is missing ${number}`);
    }
  }
});

Deno.test("the reply is short messages, not a reading — no chart, no remedy", () => {
  for (const language of LANGUAGES) {
    const bubbles = crisisReply(language);
    assertEquals(bubbles.length, 4, language);
    const text = bubbles.join(" ").toLowerCase();
    for (const word of ["rashi", "dasha", "upay", "mantra", "graha", "kundali"]) {
      assert(!text.includes(word), `${language} mentions ${word}`);
    }
  }
});

Deno.test("a blocked turn keeps Tele-MANAS within reach without assuming a crisis", () => {
  for (const language of LANGUAGES) {
    const [line] = blockedReply(language);
    assert(line.includes("14416"), language);
    assert(!line.includes("112"), `${language} treats a block as an emergency`);
  }
});

Deno.test("a chat language picks its reply, and anything unknown gets English", () => {
  assertEquals(crisisLanguageFor("Hindi"), "hindi");
  assertEquals(crisisLanguageFor(" Kannada "), "kannada");
  assertEquals(crisisLanguageFor("Klingon"), "english");
});

Deno.test("a fixed reply renders in old builds too, which need an opening", () => {
  const body = fixedReplyBody(crisisReply("hinglish"), { kind: "care", version: "v4" });

  assertEquals(body.kind, "care");
  assertEquals((body.bubbles as string[]).length, 4);
  assert(typeof body.opening === "string" && (body.opening as string).length > 0);
  assert((body.verdict as string).length > 0);
  assertEquals(body.options, []);
  assertEquals(body.ask_for, "none");

  // One bubble goes in the opening alone, never shown twice.
  const single = fixedReplyBody(["Only this."], { kind: "care", version: "v4" });
  assertEquals(single.verdict, "");
  assertEquals(single.opening, "Only this.");
});

Deno.test("a safety block is told apart from an ordinary failure", () => {
  assert(new GeminiError(null, "x", "prompt blocked: SAFETY").isSafetyBlock);
  assert(new GeminiError(null, "x", "finishReason SAFETY").isSafetyBlock);
  assert(new GeminiError(null, "x", "finishReason PROHIBITED_CONTENT").isSafetyBlock);
  assert(!new GeminiError(503, "x", "overloaded").isSafetyBlock);
  assert(!new GeminiError(null, "x", "MAX_TOKENS: response truncated").isSafetyBlock);
});
