/**
 * When someone tells Astro they want to die.
 *
 * Checked in code, before the model is called, on every chat turn and every prompt version. A
 * prompt rule alone is not enough for this: the model can be blocked, can time out, can be
 * rolled back to a version that never heard of it, and can decide the reading format matters
 * more. A fixed reply cannot do any of those things.
 *
 * The phrase lists came from a read-only scan of ten days of real messages (24 Sep 2026), which
 * found about nine genuine ones, mostly Kannada and Hindi/Hinglish — "ನಾನು ಸಾಯುತ್ತೇನೆ",
 * "ಸಾಲದ ಹೊರೆಯಿಂದ ಸಾಯಿಬೇಕೆಂದು ತೀರ್ಮಾನ ಮಾಡಿದ್ದೇನೆ", "mai mar jaunga usk bina", "mujhe wo nhi mila to
 * m mar jaungi", "jab pyar hi nahi to jina kis kaam ka", "I want to die", "…मन कर रहा है खुदकुशी".
 * The same scan is why the lists are first-person forms rather than stems: "ಸಾಯ" alone would
 * fire on ಸಾಯಂಕಾಲ, "evening", which people type every time they give a birth time.
 *
 * Some matches will be about someone else — "she said she would die". The reply is worded for
 * "you or someone close to you" so that it is still the right thing to say.
 *
 * The replies in Kannada, Tamil, Telugu, Malayalam, Marathi, Bengali and Gujarati were written
 * without a native speaker. They must be reviewed by one before they are relied on; the numbers
 * in them are the part that has been verified (Tele-MANAS and iCall, September 2026).
 */

/** A language the fixed replies exist in. */
export type CrisisLanguage =
  | "english"
  | "hinglish"
  | "hindi"
  | "marathi"
  | "kannada"
  | "tamil"
  | "telugu"
  | "malayalam"
  | "bengali"
  | "gujarati";

export interface CrisisMatch {
  /** Which list matched, for the review table. Never the text itself. */
  rule: string;

  /** The language the reply should be written in. */
  language: CrisisLanguage;
}

/** Only this much of a message is scanned — the same ceiling the handler puts on a message. */
const SCAN_CHARS = 2000;

/** No letter or vowel sign before — a word edge that works in every Indian script. */
const EDGE = "(?<![\\p{L}\\p{M}])";

interface Rule {
  rule: string;
  language: CrisisLanguage;
  pattern: RegExp;
}

function rule(name: string, language: CrisisLanguage, alternatives: string[]): Rule {
  return {
    rule: name,
    language,
    pattern: new RegExp(`${EDGE}(?:${alternatives.join("|")})`, "iu"),
  };
}

/**
 * Every list, most specific script first. Roman-letter Hindi and English share an alphabet, so
 * they come last and are told apart by which list matched.
 */
const RULES: Rule[] = [
  rule("kannada", "kannada", [
    "ಆತ್ಮಹತ್ಯೆ",
    // "I will die" / "I must die" / "decided to die" — first person and desire forms only.
    "ಸಾಯುತ್ತೇನೆ",
    "ಸಾಯುತ್ತೀನಿ",
    "ಸಾಯ್ತೀನಿ",
    "ಸಾಯ್ತಿನಿ",
    "ಸಾಯ್ತೇನೆ",
    "ಸಾಯಬೇಕು",
    "ಸಾಯಿಬೇಕು",
    "ಸಾಯಬೇಕೆಂದು",
    "ಸಾಯಿಬೇಕೆಂದು",
    "ಸತ್ತು\\s*ಹೋಗುತ್ತೇನೆ",
    "ಸತ್ತು\\s*ಹೋಗ್ತೀನಿ",
    "ಬದುಕಲು\\s*ಇಷ್ಟ\\s*ಇಲ್ಲ",
    "ಬದುಕಲು\\s*ಇಷ್ಟವಿಲ್ಲ",
    "ಬದುಕೋಕೆ\\s*ಇಷ್ಟ\\s*ಇಲ್ಲ",
  ]),
  rule("tamil", "tamil", [
    "தற்கொலை",
    "சாக\\s*வேண்டும்",
    "சாகப்\\s*போகிறேன்",
    "சாக\\s*போகிறேன்",
    "சாகணும்",
    "செத்துப்\\s*போகிறேன்",
    "செத்து\\s*போறேன்",
    "வாழ\\s*விருப்பமில்லை",
    "வாழ\\s*விருப்பம்\\s*இல்லை",
    "வாழ\\s*பிடிக்கவில்லை",
  ]),
  rule("telugu", "telugu", [
    "ఆత్మహత్య",
    "చచ్చిపోతాను",
    "చచ్చిపోవాలని",
    "చనిపోతాను",
    "చనిపోవాలని",
    "చావాలని",
    "చస్తాను",
    "బతకాలని\\s*లేదు",
    "బ్రతకాలని\\s*లేదు",
  ]),
  rule("malayalam", "malayalam", [
    "ആത്മഹത്യ",
    "മരിക്കണം",
    "മരിക്കാൻ\\s*തോന്നുന്നു",
    "ചാകണം",
    "ജീവനൊടുക്കും",
    "ജീവിക്കാൻ\\s*വയ്യ",
    "ജീവിക്കാൻ\\s*ഇഷ്ടമില്ല",
  ]),
  rule("bengali", "bengali", [
    "আত্মহত্যা",
    "মরে\\s*যেতে\\s*চাই",
    "মরতে\\s*চাই",
    "বাঁচতে\\s*চাই\\s*না",
    "বাঁচতে\\s*ইচ্ছে\\s*করে\\s*না",
  ]),
  rule("gujarati", "gujarati", [
    "આત્મહત્યા",
    "મરી\\s*જવું\\s*છે",
    "મરી\\s*જઈશ",
    "મરવું\\s*છે",
    "જીવવું\\s*નથી",
  ]),
  // Before Hindi: the two share Devanagari and आत्महत्या, and these forms are Marathi's own.
  rule("marathi", "marathi", [
    "मरायचं",
    "मरायचे",
    "मरायचा",
    "जगायचं\\s*नाही",
    "जगायचे\\s*नाही",
    "जगण्याची\\s*इच्छा\\s*नाही",
    "जीव\\s*देईन",
  ]),
  rule("hindi", "hindi", [
    "आत्महत्या",
    "खुदकुशी",
    "ख़ुदकुशी",
    "मर\\s*जा(?:ऊं|ऊँ|उं|ऊ|उ)",
    "मरना\\s*(?:चाहता|चाहती|चाहूं|चाहूँ|है)",
    "(?:जीना|जीने)\\s*(?:नहीं|नही)\\s*(?:चाह|है)",
    "जीने\\s*का\\s*(?:कोई\\s*)?(?:मन|इच्छा)\\s*(?:नहीं|नही)",
    "जीना\\s*किस\\s*काम",
    "जान\\s*दे\\s*(?:दूंगा|दूँगा|दूंगी|दूँगी|दूं|दूँ|देंगे)",
    "(?:खुद|ख़ुद|अपने\\s*आप)\\s*को\\s*(?:खत्म|ख़त्म|मार)",
    "(?:ज़हर|जहर)\\s*खा\\s*(?:लूंगा|लूँगा|लूंगी|लूँगी|लूं|लूँ)",
    "(?:फांसी|फाँसी)\\s*(?:लगा|पर)",
  ]),
  rule("english", "english", [
    "i\\s*(?:want|wanna)\\s*to\\s*die",
    "kill\\s*myself",
    "end\\s*my\\s*life",
    "take\\s*my\\s*(?:own\\s*)?life",
    "suicidal",
    // Not "she doesn't want to live with me", which is a breakup.
    "(?:don'?t|do\\s*not)\\s*want\\s*to\\s*live(?!\\s*with)",
    "no\\s*reason\\s*to\\s*live",
    "better\\s*off\\s*dead",
  ]),
  rule("hinglish", "hinglish", [
    "suicide",
    "sucide",
    "suiside",
    "khud\\s*khushi",
    "khudkushi",
    "khudkhushi",
    "aatm\\s*hatya",
    "aatmahatya",
    "atmhatya",
    // "mar jaunga", "mar jaungi", "mar jaaunga", "mar jau" — first person. "mar gaye" (someone
    // died) and "mar jayega" (he will die) are deliberately not here.
    // "mar jao" (a curse at someone else) and "mar jaoge" (you will die) are left out too.
    "mar\\s*ja+(?:u+n?(?:g[aie])?|o+n(?:g[aie])?|oo+n?(?:g[aie])?)(?![\\p{L}\\p{M}])",
    // Wanting to die — not "marna chahiye", which a typo for "maanna chahiye" (should I accept)
    // produced in a real message about a wife's condition.
    "marna\\s*(?:chaa?ha?t[ai]|chahu|chahun|hai)",
    "mar\\s*ja+na\\s*(?:chaa?ha?t[ai]|chahu|chahun|hai)",
    "(?:jeena|jina|jeene|jine)\\s*(?:nahi|nhi|nahin|nai)\\s*(?:chahta|chahti|chahiye|hai|he)",
    "(?:jeene|jine)\\s*ka\\s*(?:koi\\s*)?(?:man|mann|mood)\\s*(?:nahi|nhi|nahin)",
    "(?:jeena|jina)\\s*kis\\s*kaam\\s*ka",
    "jaan\\s*de\\s*(?:dunga|dungi|du|doon|denge)",
    "(?:khud\\s*ko|apne\\s*aap\\s*ko|apni\\s*(?:zindagi|jaan|life))\\s*(?:hi\\s*)?khatam\\s*kar",
    "(?:zeher|zehar|zahar)\\s*(?:kha|pi)\\s*(?:lu|loo|lunga|lungi)",
    "fa+n?si\\s*(?:laga|lagaa|pe|par)",
  ]),
];

/**
 * What this message says about someone wanting to end their life, or null when it says nothing.
 *
 * Errs towards firing. A false positive costs one reply that was not an answer, and the reply
 * says so and invites them to carry on; a miss costs something that cannot be taken back.
 */
export function detectCrisis(message: string): CrisisMatch | null {
  const text = message.slice(0, SCAN_CHARS);
  if (!text.trim()) return null;

  for (const { rule, language, pattern } of RULES) {
    if (pattern.test(text)) {
      // A Roman-letter match takes its language from the list; a script match could still be
      // Marathi written with a Hindi word, which the Marathi list above has already caught.
      return { rule, language: languageOf(text, language) };
    }
  }
  return null;
}

/**
 * The language to answer in, from the script the message is actually written in.
 *
 * The matching list is a good guess, and the script is a better one: a Hindi message that says
 * "suicide" in Roman letters is still a Hindi message.
 */
function languageOf(text: string, matched: CrisisLanguage): CrisisLanguage {
  const count = (pattern: RegExp) => text.match(pattern)?.length ?? 0;

  const scripts: Array<[CrisisLanguage, number]> = [
    ["kannada", count(/[ಀ-೿]/g)],
    ["tamil", count(/[஀-௿]/g)],
    ["telugu", count(/[ఀ-౿]/g)],
    ["malayalam", count(/[ഀ-ൿ]/g)],
    ["bengali", count(/[ঀ-৿]/g)],
    ["gujarati", count(/[઀-૿]/g)],
    [matched === "marathi" ? "marathi" : "hindi", count(/[ऀ-ॿ]/g)],
  ];

  const [top, letters] = scripts.reduce((best, entry) => (entry[1] > best[1] ? entry : best));
  if (letters >= 2) return top;

  return matched === "english" ? "english" : "hinglish";
}

// ---------------------------------------------------------------- the replies

/** The numbers every reply carries, as the app linkifies them. Verified September 2026. */
export const HELPLINES = [
  { name: "Tele-MANAS", number: "14416", note: "free, 24x7, English and 20 Indian languages" },
  { name: "iCall", number: "9152987821", note: "Mon-Sat, daytime" },
  { name: "Emergency", number: "112", note: "immediate danger" },
] as const;

/**
 * Four short messages: that it was heard, who to call, who to tell, and that they can carry on.
 *
 * No chart, no remedy, nothing that could be read as the planets explaining how they feel.
 */
const CRISIS_REPLIES: Record<CrisisLanguage, string[]> = {
  english: [
    "What you're feeling sounds really heavy — thank you for telling me. 🙏",
    "Please talk to someone now: call Tele-MANAS on 14416 — free, 24 hours, in your language. " +
    "iCall: 9152987821 (Mon–Sat). If you are in danger right now, call 112.",
    "Tell someone you trust — at home, or a friend — how you feel, right now. You are not alone.",
    "If I have misread you, or this is about someone close to you, tell me — I'm here.",
  ],
  hinglish: [
    "Aap jo mehsoos kar rahe hain, woh bahut bhaari hai — aur aapne bataya, yeh himmat ki baat " +
    "hai. 🙏",
    "Abhi kisi se baat kijiye: Tele-MANAS 14416 par call karein — free hai, 24 ghante, aapki " +
    "bhasha mein. iCall: 9152987821 (Som–Shani). Agar abhi khatra hai to 112 par call karein.",
    "Ghar mein kisi ko, ya kisi dost ko, abhi bataiye ki aap kaisa mehsoos kar rahe hain. Aap " +
    "akele nahi hain.",
    "Agar maine galat samjha, ya yeh kisi apne ke baare mein hai, to bataiye — main yahin hoon.",
  ],
  hindi: [
    "आप जो महसूस कर रहे हैं, वो बहुत भारी है — और आपने बताया, ये हिम्मत की बात है। 🙏",
    "अभी किसी से बात कीजिए: Tele-MANAS 14416 पर कॉल करें — मुफ़्त, 24 घंटे, आपकी भाषा में। " +
    "iCall: 9152987821 (सोम–शनि)। अगर अभी ख़तरा है तो 112 पर कॉल करें।",
    "घर में किसी को, या किसी दोस्त को, अभी बताइए कि आप कैसा महसूस कर रहे हैं। आप अकेले नहीं हैं।",
    "अगर मैंने गलत समझा, या ये किसी अपने के बारे में है, तो बताइए — मैं यहीं हूँ।",
  ],
  marathi: [
    "तुम्ही जे अनुभवत आहात ते खूप जड आहे — मला सांगितल्याबद्दल धन्यवाद. 🙏",
    "कृपया आत्ताच कोणाशी तरी बोला: Tele-MANAS 14416 वर कॉल करा — मोफत, 24 तास, तुमच्या " +
    "भाषेत. iCall: 9152987821 (सोम–शनि). आत्ता धोका असेल तर 112 वर कॉल करा.",
    "घरच्यांना किंवा विश्वासू मित्राला आत्ताच तुमच्या मनाची स्थिती सांगा. तुम्ही एकटे नाही.",
    "मी चुकीचं समजलो असेन, किंवा हे तुमच्या जवळच्या कोणाबद्दल असेल, तर सांगा — मी इथेच आहे.",
  ],
  kannada: [
    "ನೀವು ಅನುಭವಿಸುತ್ತಿರುವುದು ತುಂಬಾ ಭಾರವಾಗಿದೆ — ನನಗೆ ಹೇಳಿದ್ದಕ್ಕೆ ಧನ್ಯವಾದಗಳು. 🙏",
    "ದಯವಿಟ್ಟು ಈಗಲೇ ಯಾರೊಂದಿಗಾದರೂ ಮಾತನಾಡಿ: Tele-MANAS 14416 ಗೆ ಕರೆ ಮಾಡಿ — ಉಚಿತ, 24 ಗಂಟೆ, " +
    "ನಿಮ್ಮ ಭಾಷೆಯಲ್ಲಿ. iCall: 9152987821 (ಸೋಮ–ಶನಿ). ಈಗಲೇ ಅಪಾಯವಿದ್ದರೆ 112 ಗೆ ಕರೆ ಮಾಡಿ.",
    "ಮನೆಯವರಿಗೆ ಅಥವಾ ನಂಬಿಕೆಯ ಸ್ನೇಹಿತರಿಗೆ ಈಗಲೇ ನಿಮ್ಮ ಮನಸ್ಸಿನ ಸ್ಥಿತಿ ಹೇಳಿ. ನೀವು ಒಬ್ಬಂಟಿಯಲ್ಲ.",
    "ನಾನು ತಪ್ಪಾಗಿ ಅರ್ಥಮಾಡಿಕೊಂಡಿದ್ದರೆ, ಅಥವಾ ಇದು ನಿಮ್ಮವರ ಬಗ್ಗೆ ಆಗಿದ್ದರೆ, ಹೇಳಿ — ನಾನು ಇಲ್ಲೇ ಇದ್ದೇನೆ.",
  ],
  tamil: [
    "நீங்கள் உணர்வது மிகவும் கனமானது — என்னிடம் சொன்னதற்கு நன்றி. 🙏",
    "தயவுசெய்து இப்போதே யாரிடமாவது பேசுங்கள்: Tele-MANAS 14416 ஐ அழைக்கவும் — இலவசம், 24 மணி " +
    "நேரமும், உங்கள் மொழியில். iCall: 9152987821 (திங்கள்–சனி). இப்போதே ஆபத்து இருந்தால் 112 ஐ " +
    "அழைக்கவும்.",
    "வீட்டில் உள்ளவர்களிடமோ நம்பிக்கையான நண்பரிடமோ இப்போதே உங்கள் மனநிலையைச் சொல்லுங்கள். நீங்கள் " +
    "தனியாக இல்லை.",
    "நான் தவறாகப் புரிந்துகொண்டிருந்தால், அல்லது இது உங்கள் அன்புக்குரியவரைப் பற்றியதாக இருந்தால், " +
    "சொல்லுங்கள் — நான் இங்கேதான் இருக்கிறேன்.",
  ],
  telugu: [
    "మీరు అనుభవిస్తున్నది చాలా బరువైనది — నాతో చెప్పినందుకు ధన్యవాదాలు. 🙏",
    "దయచేసి ఇప్పుడే ఎవరితోనైనా మాట్లాడండి: Tele-MANAS 14416 కు కాల్ చేయండి — ఉచితం, 24 గంటలు, " +
    "మీ భాషలో. iCall: 9152987821 (సోమ–శని). ఇప్పుడే ప్రమాదం ఉంటే 112 కు కాల్ చేయండి.",
    "ఇంట్లో వారికి లేదా నమ్మకమైన స్నేహితుడికి ఇప్పుడే మీ మనసు ఎలా ఉందో చెప్పండి. మీరు ఒంటరి కాదు.",
    "నేను తప్పుగా అర్థం చేసుకుంటే, లేదా ఇది మీ ఆత్మీయుల గురించి అయితే, చెప్పండి — నేను ఇక్కడే ఉన్నాను.",
  ],
  malayalam: [
    "നിങ്ങൾ അനുഭവിക്കുന്നത് വളരെ ഭാരമുള്ളതാണ് — എന്നോട് പറഞ്ഞതിന് നന്ദി. 🙏",
    "ദയവായി ഇപ്പോൾ തന്നെ ആരോടെങ്കിലും സംസാരിക്കൂ: Tele-MANAS 14416 ൽ വിളിക്കൂ — സൗജന്യം, 24 " +
    "മണിക്കൂറും, നിങ്ങളുടെ ഭാഷയിൽ. iCall: 9152987821 (തിങ്കൾ–ശനി). ഇപ്പോൾ അപകടമുണ്ടെങ്കിൽ 112 ൽ " +
    "വിളിക്കൂ.",
    "വീട്ടിലുള്ളവരോടോ വിശ്വസ്തനായ സുഹൃത്തിനോടോ ഇപ്പോൾ തന്നെ നിങ്ങളുടെ മനസ്സ് പറയൂ. നിങ്ങൾ ഒറ്റയ്ക്കല്ല.",
    "ഞാൻ തെറ്റിദ്ധരിച്ചതാണെങ്കിൽ, അല്ലെങ്കിൽ ഇത് നിങ്ങളുടെ പ്രിയപ്പെട്ട ആരെയെങ്കിലും കുറിച്ചാണെങ്കിൽ, പറയൂ " +
    "— ഞാൻ ഇവിടെയുണ്ട്.",
  ],
  bengali: [
    "আপনি যা অনুভব করছেন তা খুব ভারী — আমাকে বলার জন্য ধন্যবাদ। 🙏",
    "দয়া করে এখনই কারও সঙ্গে কথা বলুন: Tele-MANAS 14416-এ ফোন করুন — বিনামূল্যে, 24 ঘণ্টা, " +
    "আপনার ভাষায়। iCall: 9152987821 (সোম–শনি)। এখনই বিপদ থাকলে 112-এ ফোন করুন।",
    "বাড়ির কাউকে বা বিশ্বস্ত বন্ধুকে এখনই আপনার মনের কথা বলুন। আপনি একা নন।",
    "আমি ভুল বুঝে থাকলে, বা এটা আপনার কাছের কারও ব্যাপারে হলে, বলুন — আমি এখানেই আছি।",
  ],
  gujarati: [
    "તમે જે અનુભવી રહ્યા છો તે ખૂબ ભારે છે — મને કહેવા બદલ આભાર. 🙏",
    "કૃપા કરીને હમણાં જ કોઈની સાથે વાત કરો: Tele-MANAS 14416 પર કૉલ કરો — મફત, 24 કલાક, તમારી " +
    "ભાષામાં. iCall: 9152987821 (સોમ–શનિ). હમણાં જોખમ હોય તો 112 પર કૉલ કરો.",
    "ઘરના કોઈને કે વિશ્વાસુ મિત્રને હમણાં જ તમારા મનની વાત કહો. તમે એકલા નથી.",
    "જો મેં ખોટું સમજ્યું હોય, અથવા આ તમારા કોઈ નજીકના વિશે હોય, તો કહો — હું અહીં જ છું.",
  ],
};

/**
 * What to say when the model refused to answer at all — a safety block.
 *
 * Not the crisis reply: a block can be about anything the filter disliked, and a helpline message
 * to someone who asked about their love life would be alarming. So it declines in one line, keeps
 * the helpline within reach without assuming, and invites another question.
 */
const BLOCKED_REPLIES: Record<CrisisLanguage, string> = {
  english: "I can't answer that one here. If you're going through something hard, Tele-MANAS " +
    "on 14416 is free and open 24 hours. Ask me anything else.",
  hinglish: "Iska jawab main yahan nahi de sakta. Agar aap pareshaan hain, to Tele-MANAS 14416 " +
    "par baat kar sakte hain — free, 24 ghante. Koi aur sawal ho to poochiye.",
  hindi: "इसका जवाब मैं यहाँ नहीं दे सकता। अगर आप परेशान हैं, तो Tele-MANAS 14416 पर बात कर " +
    "सकते हैं — मुफ़्त, 24 घंटे। कोई और सवाल हो तो पूछिए।",
  marathi: "याचं उत्तर मी इथे देऊ शकत नाही. तुम्ही अडचणीत असाल तर Tele-MANAS 14416 वर बोलू " +
    "शकता — मोफत, 24 तास. दुसरं काही विचारा.",
  kannada: "ಇದಕ್ಕೆ ನಾನು ಇಲ್ಲಿ ಉತ್ತರಿಸಲಾರೆ. ನೀವು ಕಷ್ಟದಲ್ಲಿದ್ದರೆ Tele-MANAS 14416 ಗೆ ಕರೆ ಮಾಡಬಹುದು " +
    "— ಉಚಿತ, 24 ಗಂಟೆ. ಬೇರೆ ಏನಾದರೂ ಕೇಳಿ.",
  tamil: "இதற்கு என்னால் இங்கே பதில் சொல்ல முடியாது. நீங்கள் கஷ்டத்தில் இருந்தால் Tele-MANAS " +
    "14416 ஐ அழைக்கலாம் — இலவசம், 24 மணி நேரமும். வேறு ஏதாவது கேளுங்கள்.",
  telugu: "దీనికి నేను ఇక్కడ సమాధానం ఇవ్వలేను. మీరు కష్టంలో ఉంటే Tele-MANAS 14416 కు కాల్ " +
    "చేయవచ్చు — ఉచితం, 24 గంటలు. ఇంకేదైనా అడగండి.",
  malayalam: "ഇതിന് എനിക്ക് ഇവിടെ മറുപടി പറയാൻ കഴിയില്ല. നിങ്ങൾ വിഷമത്തിലാണെങ്കിൽ Tele-MANAS " +
    "14416 ൽ വിളിക്കാം — സൗജന്യം, 24 മണിക്കൂറും. മറ്റെന്തെങ്കിലും ചോദിക്കൂ.",
  bengali: "এর উত্তর আমি এখানে দিতে পারব না। আপনি কষ্টে থাকলে Tele-MANAS 14416-এ ফোন করতে " +
    "পারেন — বিনামূল্যে, 24 ঘণ্টা। অন্য কিছু জিজ্ঞেস করুন।",
  gujarati: "આનો જવાબ હું અહીં આપી શકતો નથી. તમે મુશ્કેલીમાં હો તો Tele-MANAS 14416 પર વાત " +
    "કરી શકો — મફત, 24 કલાક. બીજું કંઈ પૂછો.",
};

/** The fixed reply for a crisis message, in [language]. */
export function crisisReply(language: CrisisLanguage): string[] {
  return [...CRISIS_REPLIES[language]];
}

/** The fixed reply for a turn the model was blocked from answering, in [language]. */
export function blockedReply(language: CrisisLanguage): string[] {
  return [BLOCKED_REPLIES[language]];
}

/**
 * The crisis language for a chat language name as the dashboard spells it ("Hindi"), so a
 * blocked reply follows the language the conversation is in. Unknown names get English.
 */
export function crisisLanguageFor(chatLanguage: string): CrisisLanguage {
  const key = chatLanguage.trim().toLowerCase();
  return (key in CRISIS_REPLIES ? key : "english") as CrisisLanguage;
}

/**
 * A reply made of [bubbles], in every shape a client might read.
 *
 * `bubbles` for the new chat screen, and `verdict` + `opening` for builds that predate it —
 * `AstroMessage.fromServer` in those drops any Astro turn without an `opening`, so a fixed reply
 * without one would simply not appear.
 */
export function fixedReplyBody(
  bubbles: string[],
  { kind, version }: { kind: "care"; version: string },
): Record<string, unknown> {
  const [first, ...rest] = bubbles;
  return {
    verdict: rest.length > 0 ? first : "",
    title_emoji: "",
    title: "",
    opening: rest.length > 0 ? rest.join("\n\n") : first,
    sections: [],
    options: [],
    ask_for: "none",
    bubbles,
    kind,
    offer: "none",
    v: version,
  };
}
