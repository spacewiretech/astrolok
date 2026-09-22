/**
 * What the daily drip says: twenty variants, each in the app's seven languages.
 *
 * The drip is different from the fourteen event campaigns in `notification_copy.ts`, and needs its
 * own shape for two reasons.
 *
 * **It repeats.** The same person gets the palm slot every day, so one fixed sentence would be
 * wallpaper by Thursday. Each slot therefore has a small pool and `drip_variant()` in SQL picks from
 * it by hashing (user, IST date, slot) — the same person gets different words tomorrow, two people
 * get different words today, and nothing about the choice is random or model-written.
 *
 * **It knows what you have done.** Every feature slot has two states. `new` is for someone who has
 * never scanned a palm, never cast a kundali; `ask` is for someone who has, and is told to take it to
 * Astro instead. Nobody is ever invited to cast the kundali they already own.
 *
 * Three placeholders, and only three: `{name}` (as in `notification_copy.ts`), `{colour}` and
 * `{planet}`. The last two come from [LUCKY_DAY], a fixed weekday table — Sunday is the Sun's and its
 * colour is orange, and that is true every Sunday forever, so no model and no stored state is
 * involved in producing "wear green today".
 *
 * Script follows `chat_language.ts`, as the event copy does: Hinglish and English in Roman letters,
 * the others in their own script, with "Astro" and "Astrolok" left in Latin everywhere.
 * **Telugu, Tamil, Kannada, Malayalam and Hindi need review by a native speaker before the drip is
 * switched on.** Twenty variants is a lot of unreviewed sentences to put on a lock screen.
 */

import { DripSlot, DripState, istDate } from "./notification_campaigns.ts";
import { CopyLanguage, COPY_LANGUAGES, fill, nameFor, PushCopy } from "./notification_copy.ts";

/**
 * One variant. `ask` is the question typed into Astro Chat when this push is tapped — it appears in
 * the transcript as the user's own words, so it is written in their language, not in English.
 */
export interface DripCopy extends PushCopy {
  ask?: string;
}

/**
 * `<slot>[_<state>]_<index>`, plus the six `locked_*` shared by every slot.
 *
 * The pool size lives here and only here. `drip_variant()` in SQL returns a raw 28-bit hash and
 * [dripVariantFor] takes it modulo the pool — so adding a twenty-seventh variant is an edit to this
 * file, not a migration, and the two counts cannot drift apart.
 */
export const DRIP_VARIANT_KEYS = [
  "today_0",
  "today_1",
  "today_2",
  "today_3",
  "palm_new_0",
  "palm_new_1",
  "palm_ask_0",
  "palm_ask_1",
  "kundali_new_0",
  "kundali_new_1",
  "kundali_ask_0",
  "kundali_ask_1",
  "face_new_0",
  "face_new_1",
  "face_ask_0",
  "face_ask_1",
  "chat_0",
  "chat_1",
  "evening_new_0",
  "evening_ask_0",
  // Shared by all six slots, for an account that is not entitled. Kept as one pool rather than one
  // per slot so a never-paid reader still gets six different sentences in a day and a different
  // arrangement tomorrow — the slot is in the hash, so the rotation is per slot as well as per day.
  "locked_0",
  "locked_1",
  "locked_2",
  "locked_3",
  "locked_4",
  "locked_5",
] as const;
export type DripVariantKey = typeof DRIP_VARIANT_KEYS[number];

export function isDripVariantKey(value: unknown): value is DripVariantKey {
  return typeof value === "string" && (DRIP_VARIANT_KEYS as readonly string[]).includes(value);
}

// ---------------------------------------------------------------- the weekday table

/** The nine grahas, named as `kundali_chart.ts` names them — English western, Hinglish Sanskrit. */
export const PLANET_NAMES: Record<CopyLanguage, Record<string, string>> = {
  english: { sun: "the Sun", moon: "the Moon", mars: "Mars", mercury: "Mercury", jupiter: "Jupiter", venus: "Venus", saturn: "Saturn", rahu: "Rahu", ketu: "Ketu" },
  hinglish: { sun: "Surya", moon: "Chandra", mars: "Mangal", mercury: "Budh", jupiter: "Guru", venus: "Shukra", saturn: "Shani", rahu: "Rahu", ketu: "Ketu" },
  hindi: { sun: "सूर्य", moon: "चंद्रमा", mars: "मंगल", mercury: "बुध", jupiter: "गुरु", venus: "शुक्र", saturn: "शनि", rahu: "राहु", ketu: "केतु" },
  telugu: { sun: "సూర్యుడు", moon: "చంద్రుడు", mars: "కుజుడు", mercury: "బుధుడు", jupiter: "గురువు", venus: "శుక్రుడు", saturn: "శని", rahu: "రాహువు", ketu: "కేతువు" },
  tamil: { sun: "சூரியன்", moon: "சந்திரன்", mars: "செவ்வாய்", mercury: "புதன்", jupiter: "குரு", venus: "சுக்கிரன்", saturn: "சனி", rahu: "ராகு", ketu: "கேது" },
  kannada: { sun: "ಸೂರ್ಯ", moon: "ಚಂದ್ರ", mars: "ಮಂಗಳ", mercury: "ಬುಧ", jupiter: "ಗುರು", venus: "ಶುಕ್ರ", saturn: "ಶನಿ", rahu: "ರಾಹು", ketu: "ಕೇತು" },
  malayalam: { sun: "സൂര്യൻ", moon: "ചന്ദ്രൻ", mars: "ചൊവ്വ", mercury: "ബുധൻ", jupiter: "ഗുരു", venus: "ശുക്രൻ", saturn: "ശനി", rahu: "രാഹു", ketu: "കേതു" },
};

/** Which graha owns which weekday. Index 0 is Sunday, as `Date.getUTCDay()` counts. */
export const WEEKDAY_LORD = ["sun", "moon", "mars", "mercury", "jupiter", "venus", "saturn"] as const;

/**
 * The colour of each weekday, indexed like [WEEKDAY_LORD].
 *
 * Sunday orange for the Sun, Monday white for the Moon, Tuesday red for Mars, Wednesday green for
 * Mercury, Thursday yellow for Jupiter, Friday pink for Venus, Saturday blue for Saturn. This is the
 * ordinary almanac mapping; it is fixed, so the same Wednesday is green for everyone, everywhere, and
 * the answer needs no computation beyond reading the date.
 */
export const LUCKY_COLOURS: Record<CopyLanguage, readonly string[]> = {
  english: ["orange", "white", "red", "green", "yellow", "pink", "blue"],
  hinglish: ["orange", "safed", "laal", "hara", "peela", "gulaabi", "neela"],
  hindi: ["नारंगी", "सफ़ेद", "लाल", "हरा", "पीला", "गुलाबी", "नीला"],
  telugu: ["నారింజ", "తెలుపు", "ఎరుపు", "ఆకుపచ్చ", "పసుపు", "గులాబీ", "నీలం"],
  tamil: ["ஆரஞ்சு", "வெள்ளை", "சிவப்பு", "பச்சை", "மஞ்சள்", "இளஞ்சிவப்பு", "நீலம்"],
  kannada: ["ಕಿತ್ತಳೆ", "ಬಿಳಿ", "ಕೆಂಪು", "ಹಸಿರು", "ಹಳದಿ", "ಗುಲಾಬಿ", "ನೀಲಿ"],
  malayalam: ["ഓറഞ്ച്", "വെള്ള", "ചുവപ്പ്", "പച്ച", "മഞ്ഞ", "പിങ്ക്", "നീല"],
};

/** The IST day of the week, 0 = Sunday. Taken off the IST calendar date, not the server's clock. */
export function istWeekday(now: Date): number {
  return new Date(`${istDate(now)}T00:00:00Z`).getUTCDay();
}

/** What to wear today and who owns the day, in one language. */
export function luckyDay(language: CopyLanguage, now: Date): { planet: string; colour: string } {
  const day = istWeekday(now);
  return {
    planet: PLANET_NAMES[language][WEEKDAY_LORD[day]],
    colour: LUCKY_COLOURS[language][day],
  };
}

// ---------------------------------------------------------------- the copy

export const DRIP_COPY: Record<DripVariantKey, Record<CopyLanguage, DripCopy>> = {
  // ---- 08:00, the day ahead. Always opens chat, always carries the colour. ----
  today_0: {
    english: { title: "Wear {colour} today 💫", body: "{name}, {planet} rules this day. Ask Astro what else it has planned for you.", ask: "What does today hold for me?" },
    hinglish: { title: "Aaj {colour} pehniye 💫", body: "{name}, aaj ka din {planet} ka hai. Astro se poochiye aur kya likha hai.", ask: "Aaj mera din kaisa rahega?" },
    hindi: { title: "आज {colour} पहनिए 💫", body: "{name}, आज का दिन {planet} का है। Astro से पूछिए और क्या लिखा है।", ask: "आज मेरा दिन कैसा रहेगा?" },
    telugu: { title: "ఈరోజు {colour} ధరించండి 💫", body: "{name}, ఈ రోజు {planet} ది. ఇంకా ఏముందో Astro ను అడగండి.", ask: "ఈరోజు నా రోజు ఎలా ఉంటుంది?" },
    tamil: { title: "இன்று {colour} அணியுங்கள் 💫", body: "{name}, இன்றைய நாள் {planet} உடையது. மீதி என்ன என்று Astro-விடம் கேளுங்கள்.", ask: "இன்று என் நாள் எப்படி இருக்கும்?" },
    kannada: { title: "ಇಂದು {colour} ಧರಿಸಿ 💫", body: "{name}, ಈ ದಿನ {planet} ದು. ಉಳಿದದ್ದನ್ನು Astro ಅನ್ನು ಕೇಳಿ.", ask: "ಇಂದು ನನ್ನ ದಿನ ಹೇಗಿರುತ್ತದೆ?" },
    malayalam: { title: "ഇന്ന് {colour} ധരിക്കൂ 💫", body: "{name}, ഇന്നത്തെ ദിവസം {planet} ന്റേതാണ്. ബാക്കി എന്തെന്ന് Astro-യോട് ചോദിക്കൂ.", ask: "ഇന്ന് എന്റെ ദിവസം എങ്ങനെയായിരിക്കും?" },
  },
  today_1: {
    english: { title: "Today belongs to {planet}", body: "{colour} is your colour for luck today. One question, and Astro tells you the rest.", ask: "What does today hold for me?" },
    hinglish: { title: "Aaj ka din {planet} ka hai", body: "{colour} aaj aapka shubh rang hai. Ek sawaal, aur Astro baaki bata dega.", ask: "Aaj mera din kaisa rahega?" },
    hindi: { title: "आज का दिन {planet} का है", body: "{colour} आज आपका शुभ रंग है। एक सवाल, और Astro बाकी बता देगा।", ask: "आज मेरा दिन कैसा रहेगा?" },
    telugu: { title: "ఈ రోజు {planet} ది", body: "{colour} ఈరోజు మీ అదృష్ట రంగు. ఒక ప్రశ్న, మిగతాది Astro చెబుతుంది.", ask: "ఈరోజు నా రోజు ఎలా ఉంటుంది?" },
    tamil: { title: "இன்றைய நாள் {planet} உடையது", body: "{colour} இன்று உங்கள் அதிர்ஷ்ட நிறம். ஒரு கேள்வி, மீதியை Astro சொல்லும்.", ask: "இன்று என் நாள் எப்படி இருக்கும்?" },
    kannada: { title: "ಈ ದಿನ {planet} ದು", body: "{colour} ಇಂದು ನಿಮ್ಮ ಅದೃಷ್ಟದ ಬಣ್ಣ. ಒಂದು ಪ್ರಶ್ನೆ, ಉಳಿದದ್ದನ್ನು Astro ಹೇಳುತ್ತದೆ.", ask: "ಇಂದು ನನ್ನ ದಿನ ಹೇಗಿರುತ್ತದೆ?" },
    malayalam: { title: "ഇന്നത്തെ ദിവസം {planet} ന്റേത്", body: "{colour} ഇന്ന് നിങ്ങളുടെ ഭാഗ്യ നിറം. ഒരു ചോദ്യം, ബാക്കി Astro പറയും.", ask: "ഇന്ന് എന്റെ ദിവസം എങ്ങനെയായിരിക്കും?" },
  },
  today_2: {
    english: { title: "Something shifts today 🌙", body: "{name}, keep {colour} close. Astro can tell you where the day is pointing.", ask: "What is the energy of my day today?" },
    hinglish: { title: "Aaj kuch badal raha hai 🌙", body: "{name}, {colour} paas rakhiye. Astro bata sakta hai din kis taraf ja raha hai.", ask: "Aaj mere din ki energy kaisi hai?" },
    hindi: { title: "आज कुछ बदल रहा है 🌙", body: "{name}, {colour} पास रखिए। Astro बता सकता है दिन किस ओर जा रहा है।", ask: "आज मेरे दिन की ऊर्जा कैसी है?" },
    telugu: { title: "ఈరోజు ఏదో మారుతోంది 🌙", body: "{name}, {colour} దగ్గర ఉంచుకోండి. రోజు ఎటు వైపు వెళ్తోందో Astro చెప్పగలదు.", ask: "ఈరోజు నా రోజు శక్తి ఎలా ఉంది?" },
    tamil: { title: "இன்று ஏதோ மாறுகிறது 🌙", body: "{name}, {colour} அருகில் வையுங்கள். நாள் எங்கே செல்கிறது என்று Astro சொல்லும்.", ask: "இன்று என் நாளின் ஆற்றல் எப்படி?" },
    kannada: { title: "ಇಂದು ಏನೋ ಬದಲಾಗುತ್ತಿದೆ 🌙", body: "{name}, {colour} ಹತ್ತಿರ ಇಟ್ಟುಕೊಳ್ಳಿ. ದಿನ ಎತ್ತ ಸಾಗುತ್ತಿದೆ ಎಂದು Astro ಹೇಳಬಲ್ಲದು.", ask: "ಇಂದು ನನ್ನ ದಿನದ ಶಕ್ತಿ ಹೇಗಿದೆ?" },
    malayalam: { title: "ഇന്ന് എന്തോ മാറുന്നു 🌙", body: "{name}, {colour} അടുത്ത് വയ്ക്കൂ. ദിവസം എങ്ങോട്ടെന്ന് Astro പറയും.", ask: "ഇന്ന് എന്റെ ദിവസത്തിന്റെ ഊർജ്ജം എങ്ങനെ?" },
  },
  today_3: {
    english: { title: "Your day is already written", body: "{planet} is holding the pen. Wear {colour}, and ask Astro what it says.", ask: "What does today hold for me?" },
    hinglish: { title: "Aapka din pehle se likha hai", body: "Kalam {planet} ke haath mein hai. {colour} pehniye, aur Astro se poochiye.", ask: "Aaj mera din kaisa rahega?" },
    hindi: { title: "आपका दिन पहले से लिखा है", body: "कलम {planet} के हाथ में है। {colour} पहनिए, और Astro से पूछिए।", ask: "आज मेरा दिन कैसा रहेगा?" },
    telugu: { title: "మీ రోజు ఇప్పటికే రాయబడింది", body: "కలం {planet} చేతిలో ఉంది. {colour} ధరించి, Astro ను అడగండి.", ask: "ఈరోజు నా రోజు ఎలా ఉంటుంది?" },
    tamil: { title: "உங்கள் நாள் ஏற்கனவே எழுதப்பட்டது", body: "பேனா {planet} கையில். {colour} அணிந்து, Astro-விடம் கேளுங்கள்.", ask: "இன்று என் நாள் எப்படி இருக்கும்?" },
    kannada: { title: "ನಿಮ್ಮ ದಿನ ಈಗಾಗಲೇ ಬರೆದಾಗಿದೆ", body: "ಲೇಖನಿ {planet} ಕೈಯಲ್ಲಿದೆ. {colour} ಧರಿಸಿ, Astro ಅನ್ನು ಕೇಳಿ.", ask: "ಇಂದು ನನ್ನ ದಿನ ಹೇಗಿರುತ್ತದೆ?" },
    malayalam: { title: "നിങ്ങളുടെ ദിവസം എഴുതിക്കഴിഞ്ഞു", body: "പേന {planet} ന്റെ കൈയിലാണ്. {colour} ധരിക്കൂ, Astro-യോട് ചോദിക്കൂ.", ask: "ഇന്ന് എന്റെ ദിവസം എങ്ങനെയായിരിക്കും?" },
  },

  // ---- 10:30, the palm. `new` opens the camera; `ask` opens chat. ----
  palm_new_0: {
    english: { title: "Your hand is a map 🖐️", body: "{name}, thirty seconds and eight lines. See where yours are taking you." },
    hinglish: { title: "Aapka haath ek naksha hai 🖐️", body: "{name}, tees second aur aath lakeerein. Dekhiye ve aapko kahan le ja rahi hain." },
    hindi: { title: "आपका हाथ एक नक्शा है 🖐️", body: "{name}, तीस सेकंड और आठ रेखाएं। देखिए वे आपको कहां ले जा रही हैं।" },
    telugu: { title: "మీ చెయ్యి ఒక పటం 🖐️", body: "{name}, ముప్పై సెకన్లు, ఎనిమిది రేఖలు. అవి మిమ్మల్ని ఎటు తీసుకెళ్తున్నాయో చూడండి." },
    tamil: { title: "உங்கள் கை ஒரு வரைபடம் 🖐️", body: "{name}, முப்பது வினாடிகள், எட்டு கோடுகள். அவை உங்களை எங்கே அழைத்துச் செல்கின்றன பாருங்கள்." },
    kannada: { title: "ನಿಮ್ಮ ಕೈ ಒಂದು ನಕ್ಷೆ 🖐️", body: "{name}, ಮೂವತ್ತು ಸೆಕೆಂಡು, ಎಂಟು ಗೆರೆಗಳು. ಅವು ನಿಮ್ಮನ್ನು ಎಲ್ಲಿಗೆ ಕೊಂಡೊಯ್ಯುತ್ತಿವೆ ನೋಡಿ." },
    malayalam: { title: "നിങ്ങളുടെ കൈ ഒരു ഭൂപടം 🖐️", body: "{name}, മുപ്പത് സെക്കൻഡ്, എട്ട് രേഖകൾ. അവ നിങ്ങളെ എങ്ങോട്ട് കൊണ്ടുപോകുന്നു എന്ന് കാണൂ." },
  },
  palm_new_1: {
    english: { title: "Nobody else has your lines", body: "Heart, life, head, fate — and four more. Read them before the day turns." },
    hinglish: { title: "Aisi lakeerein aur kisi ki nahi", body: "Dil, jeevan, dimaag, bhagya — aur chaar aur. Din dhalne se pehle padhiye." },
    hindi: { title: "ऐसी रेखाएं और किसी की नहीं", body: "हृदय, जीवन, मस्तिष्क, भाग्य — और चार और। दिन ढलने से पहले पढ़िए।" },
    telugu: { title: "మీ రేఖలు మరెవరికీ లేవు", body: "హృదయం, జీవితం, మనసు, భాగ్యం — ఇంకా నాలుగు. రోజు గడిచేలోపు చదవండి." },
    tamil: { title: "உங்கள் கோடுகள் வேறு யாருக்கும் இல்லை", body: "இதயம், வாழ்க்கை, மனம், விதி — இன்னும் நான்கு. நாள் முடியும் முன் படியுங்கள்." },
    kannada: { title: "ನಿಮ್ಮ ಗೆರೆಗಳು ಬೇರೆ ಯಾರಿಗೂ ಇಲ್ಲ", body: "ಹೃದಯ, ಜೀವನ, ಮನಸ್ಸು, ಭಾಗ್ಯ — ಇನ್ನೂ ನಾಲ್ಕು. ದಿನ ಮುಗಿಯುವ ಮೊದಲು ಓದಿ." },
    malayalam: { title: "ഈ രേഖകൾ മറ്റാർക്കുമില്ല", body: "ഹൃദയം, ജീവിതം, മനസ്സ്, വിധി — ഇനിയും നാല്. ദിവസം തീരും മുൻപ് വായിക്കൂ." },
  },
  palm_ask_0: {
    english: { title: "Your palm already knows", body: "{name}, ask Astro what your hand says about today.", ask: "What does my palm reading say about my day today?" },
    hinglish: { title: "Aapki hatheli pehle se jaanti hai", body: "{name}, Astro se poochiye aapka haath aaj ke baare mein kya kehta hai.", ask: "Meri hatheli ki reading aaj mere din ke baare mein kya kehti hai?" },
    hindi: { title: "आपकी हथेली पहले से जानती है", body: "{name}, Astro से पूछिए आपका हाथ आज के बारे में क्या कहता है।", ask: "मेरी हथेली की रीडिंग आज मेरे दिन के बारे में क्या कहती है?" },
    telugu: { title: "మీ అరచేతికి ముందే తెలుసు", body: "{name}, ఈరోజు గురించి మీ చెయ్యి ఏమి చెబుతుందో Astro ను అడగండి.", ask: "నా అరచేతి రీడింగ్ ఈరోజు నా రోజు గురించి ఏమి చెబుతుంది?" },
    tamil: { title: "உங்கள் உள்ளங்கைக்கு ஏற்கனவே தெரியும்", body: "{name}, இன்றைக்கு உங்கள் கை என்ன சொல்கிறது என்று Astro-விடம் கேளுங்கள்.", ask: "என் கைரேகை வாசிப்பு இன்று என் நாளைப் பற்றி என்ன சொல்கிறது?" },
    kannada: { title: "ನಿಮ್ಮ ಅಂಗೈಗೆ ಈಗಾಗಲೇ ಗೊತ್ತು", body: "{name}, ಇಂದಿನ ಬಗ್ಗೆ ನಿಮ್ಮ ಕೈ ಏನು ಹೇಳುತ್ತದೆ ಎಂದು Astro ಅನ್ನು ಕೇಳಿ.", ask: "ನನ್ನ ಅಂಗೈ ರೀಡಿಂಗ್ ಇಂದು ನನ್ನ ದಿನದ ಬಗ್ಗೆ ಏನು ಹೇಳುತ್ತದೆ?" },
    malayalam: { title: "നിങ്ങളുടെ കൈപ്പത്തിക്ക് അറിയാം", body: "{name}, ഇന്നത്തെക്കുറിച്ച് നിങ്ങളുടെ കൈ എന്ത് പറയുന്നു എന്ന് Astro-യോട് ചോദിക്കൂ.", ask: "എന്റെ കൈരേഖാ വായന ഇന്നത്തെ ദിവസത്തെക്കുറിച്ച് എന്ത് പറയുന്നു?" },
  },
  palm_ask_1: {
    english: { title: "Bring your palm a question", body: "You've had it read. Ask Astro what those lines mean for this week.", ask: "What do my palm lines mean for me this week?" },
    hinglish: { title: "Apni hatheli se ek sawaal poochiye", body: "Reading ho chuki hai. Astro se poochiye ye lakeerein is hafte ke liye kya kehti hain.", ask: "Meri hatheli ki lakeerein is hafte mere liye kya kehti hain?" },
    hindi: { title: "अपनी हथेली से एक सवाल पूछिए", body: "रीडिंग हो चुकी है। Astro से पूछिए ये रेखाएं इस हफ़्ते के लिए क्या कहती हैं।", ask: "मेरी हथेली की रेखाएं इस हफ़्ते मेरे लिए क्या कहती हैं?" },
    telugu: { title: "మీ అరచేతిని ఒక ప్రశ్న అడగండి", body: "రీడింగ్ అయిపోయింది. ఈ వారానికి ఆ రేఖలు ఏమి చెబుతున్నాయో Astro ను అడగండి.", ask: "నా అరచేతి రేఖలు ఈ వారం నాకు ఏమి చెబుతున్నాయి?" },
    tamil: { title: "உங்கள் கையிடம் ஒரு கேள்வி", body: "வாசிப்பு முடிந்தது. இந்த வாரத்திற்கு அந்தக் கோடுகள் என்ன சொல்கின்றன என்று Astro-விடம் கேளுங்கள்.", ask: "என் கைரேகைகள் இந்த வாரம் எனக்கு என்ன சொல்கின்றன?" },
    kannada: { title: "ನಿಮ್ಮ ಅಂಗೈಗೆ ಒಂದು ಪ್ರಶ್ನೆ ಕೇಳಿ", body: "ರೀಡಿಂಗ್ ಆಗಿದೆ. ಈ ವಾರಕ್ಕೆ ಆ ಗೆರೆಗಳು ಏನು ಹೇಳುತ್ತವೆ ಎಂದು Astro ಅನ್ನು ಕೇಳಿ.", ask: "ನನ್ನ ಅಂಗೈ ಗೆರೆಗಳು ಈ ವಾರ ನನಗೆ ಏನು ಹೇಳುತ್ತವೆ?" },
    malayalam: { title: "കൈപ്പത്തിയോട് ഒരു ചോദ്യം ചോദിക്കൂ", body: "വായന കഴിഞ്ഞു. ഈ ആഴ്ചയ്ക്ക് ആ രേഖകൾ എന്ത് പറയുന്നു എന്ന് Astro-യോട് ചോദിക്കൂ.", ask: "എന്റെ കൈരേഖകൾ ഈ ആഴ്ച എനിക്ക് എന്ത് പറയുന്നു?" },
  },

  // ---- 13:00, the kundali. `new` only ever reaches someone who has never cast one. ----
  kundali_new_0: {
    english: { title: "Your chart hasn't been cast", body: "{name}, your birth details are saved. One tap and the planets do the rest." },
    hinglish: { title: "Aapki kundali abhi bani nahi", body: "{name}, aapki janm jaankari save hai. Ek tap, baaki grah sambhal lenge." },
    hindi: { title: "आपकी कुंडली अभी बनी नहीं", body: "{name}, आपकी जन्म जानकारी सेव है। एक टैप, बाकी ग्रह संभाल लेंगे।" },
    telugu: { title: "మీ జాతకం ఇంకా తయారవలేదు", body: "{name}, మీ జనన వివరాలు సేవ్ అయ్యాయి. ఒక ట్యాప్, మిగతాది గ్రహాలు చూసుకుంటాయి." },
    tamil: { title: "உங்கள் ஜாதகம் இன்னும் உருவாகவில்லை", body: "{name}, உங்கள் பிறப்பு விவரங்கள் சேமிக்கப்பட்டுள்ளன. ஒரு தட்டல், மீதியை கிரகங்கள் பார்த்துக்கொள்ளும்." },
    kannada: { title: "ನಿಮ್ಮ ಜಾತಕ ಇನ್ನೂ ಆಗಿಲ್ಲ", body: "{name}, ನಿಮ್ಮ ಜನ್ಮ ವಿವರಗಳು ಉಳಿಸಿವೆ. ಒಂದು ಟ್ಯಾಪ್, ಉಳಿದದ್ದನ್ನು ಗ್ರಹಗಳು ನೋಡಿಕೊಳ್ಳುತ್ತವೆ." },
    malayalam: { title: "നിങ്ങളുടെ ജാതകം ഇനിയും ആയിട്ടില്ല", body: "{name}, ജനന വിവരങ്ങൾ സേവ് ചെയ്തിട്ടുണ്ട്. ഒരു ടാപ്പ്, ബാക്കി ഗ്രഹങ്ങൾ നോക്കിക്കോളും." },
  },
  kundali_new_1: {
    english: { title: "Nine planets, one moment 🪐", body: "The sky at the hour you were born is still up there. See what it wrote." },
    hinglish: { title: "Nau grah, ek lamha 🪐", body: "Jis ghadi aap paida hue, vo aasmaan aaj bhi upar hai. Dekhiye usne kya likha." },
    hindi: { title: "नौ ग्रह, एक पल 🪐", body: "जिस घड़ी आप पैदा हुए, वो आसमान आज भी ऊपर है। देखिए उसने क्या लिखा।" },
    telugu: { title: "తొమ్మిది గ్రహాలు, ఒక క్షణం 🪐", body: "మీరు పుట్టిన గడియ ఆకాశం ఇప్పటికీ పైనే ఉంది. అది ఏమి రాసిందో చూడండి." },
    tamil: { title: "ஒன்பது கிரகங்கள், ஒரு கணம் 🪐", body: "நீங்கள் பிறந்த நேரத்து வானம் இன்னும் மேலே இருக்கிறது. அது எழுதியதைப் பாருங்கள்." },
    kannada: { title: "ಒಂಬತ್ತು ಗ್ರಹಗಳು, ಒಂದು ಕ್ಷಣ 🪐", body: "ನೀವು ಹುಟ್ಟಿದ ಗಳಿಗೆಯ ಆಕಾಶ ಇಂದಿಗೂ ಮೇಲಿದೆ. ಅದು ಬರೆದದ್ದನ್ನು ನೋಡಿ." },
    malayalam: { title: "ഒൻപത് ഗ്രഹങ്ങൾ, ഒരു നിമിഷം 🪐", body: "നിങ്ങൾ ജനിച്ച നേരത്തെ ആകാശം ഇപ്പോഴും മുകളിലുണ്ട്. അത് എഴുതിയത് കാണൂ." },
  },
  kundali_ask_0: {
    english: { title: "Your Kundali has more to say", body: "{name}, ask Astro what your chart says about right now.", ask: "What does my kundali say about my life right now?" },
    hinglish: { title: "Aapki Kundali mein aur bhi hai", body: "{name}, Astro se poochiye aapki kundali abhi ke baare mein kya kehti hai.", ask: "Meri kundali abhi meri zindagi ke baare mein kya kehti hai?" },
    hindi: { title: "आपकी कुंडली में और भी है", body: "{name}, Astro से पूछिए आपकी कुंडली अभी के बारे में क्या कहती है।", ask: "मेरी कुंडली अभी मेरी ज़िंदगी के बारे में क्या कहती है?" },
    telugu: { title: "మీ జాతకంలో ఇంకా ఉంది", body: "{name}, ఇప్పటి గురించి మీ జాతకం ఏమి చెబుతుందో Astro ను అడగండి.", ask: "నా జాతకం ఇప్పుడు నా జీవితం గురించి ఏమి చెబుతుంది?" },
    tamil: { title: "உங்கள் ஜாதகத்தில் இன்னும் உள்ளது", body: "{name}, இப்போதைக்கு உங்கள் ஜாதகம் என்ன சொல்கிறது என்று Astro-விடம் கேளுங்கள்.", ask: "என் ஜாதகம் இப்போது என் வாழ்க்கையைப் பற்றி என்ன சொல்கிறது?" },
    kannada: { title: "ನಿಮ್ಮ ಜಾತಕದಲ್ಲಿ ಇನ್ನೂ ಇದೆ", body: "{name}, ಈಗಿನ ಬಗ್ಗೆ ನಿಮ್ಮ ಜಾತಕ ಏನು ಹೇಳುತ್ತದೆ ಎಂದು Astro ಅನ್ನು ಕೇಳಿ.", ask: "ನನ್ನ ಜಾತಕ ಈಗ ನನ್ನ ಜೀವನದ ಬಗ್ಗೆ ಏನು ಹೇಳುತ್ತದೆ?" },
    malayalam: { title: "ജാതകത്തിൽ ഇനിയും പറയാനുണ്ട്", body: "{name}, ഇപ്പോഴത്തെക്കുറിച്ച് നിങ്ങളുടെ ജാതകം എന്ത് പറയുന്നു എന്ന് Astro-യോട് ചോദിക്കൂ.", ask: "എന്റെ ജാതകം ഇപ്പോൾ എന്റെ ജീവിതത്തെക്കുറിച്ച് എന്ത് പറയുന്നു?" },
  },
  kundali_ask_1: {
    english: { title: "Ask your chart a real question", body: "Astro has your birth chart open. Love, money, the year ahead — pick one.", ask: "What does my birth chart say about the year ahead?" },
    hinglish: { title: "Kundali se asli sawaal poochiye", body: "Astro ke saamne aapki janm kundali khuli hai. Pyaar, paisa, aane wala saal — chuniye.", ask: "Meri janm kundali aane wale saal ke baare mein kya kehti hai?" },
    hindi: { title: "कुंडली से असली सवाल पूछिए", body: "Astro के सामने आपकी जन्म कुंडली खुली है। प्यार, पैसा, आने वाला साल — चुनिए।", ask: "मेरी जन्म कुंडली आने वाले साल के बारे में क्या कहती है?" },
    telugu: { title: "జాతకాన్ని నిజమైన ప్రశ్న అడగండి", body: "Astro ముందు మీ జన్మ కుండలి తెరిచి ఉంది. ప్రేమ, డబ్బు, రాబోయే సంవత్సరం — ఒకటి ఎంచుకోండి.", ask: "నా జన్మ కుండలి రాబోయే సంవత్సరం గురించి ఏమి చెబుతుంది?" },
    tamil: { title: "ஜாதகத்திடம் உண்மையான கேள்வி", body: "Astro முன் உங்கள் ஜனன ஜாதகம் திறந்திருக்கிறது. காதல், பணம், வரும் ஆண்டு — ஒன்றைத் தேர்வு செய்யுங்கள்.", ask: "என் ஜனன ஜாதகம் வரும் ஆண்டைப் பற்றி என்ன சொல்கிறது?" },
    kannada: { title: "ಜಾತಕಕ್ಕೆ ನಿಜವಾದ ಪ್ರಶ್ನೆ ಕೇಳಿ", body: "Astro ಮುಂದೆ ನಿಮ್ಮ ಜನ್ಮ ಕುಂಡಲಿ ತೆರೆದಿದೆ. ಪ್ರೀತಿ, ಹಣ, ಮುಂದಿನ ವರ್ಷ — ಒಂದನ್ನು ಆರಿಸಿ.", ask: "ನನ್ನ ಜನ್ಮ ಕುಂಡಲಿ ಮುಂದಿನ ವರ್ಷದ ಬಗ್ಗೆ ಏನು ಹೇಳುತ್ತದೆ?" },
    malayalam: { title: "ജാതകത്തോട് യഥാർത്ഥ ചോദ്യം ചോദിക്കൂ", body: "Astro-യുടെ മുന്നിൽ നിങ്ങളുടെ ജനന ജാതകം തുറന്നിരിക്കുന്നു. പ്രണയം, പണം, വരും വർഷം — ഒന്ന് തിരഞ്ഞെടുക്കൂ.", ask: "എന്റെ ജനന ജാതകം വരും വർഷത്തെക്കുറിച്ച് എന്ത് പറയുന്നു?" },
  },

  // ---- 15:30, the face. ----
  face_new_0: {
    english: { title: "Your face is keeping secrets", body: "{name}, six features, read the way Samudrika Shastra reads them." },
    hinglish: { title: "Aapka chehra raaz chhupa raha hai", body: "{name}, chhe lakshan, Samudrika Shastra ke tareeke se padhe gaye." },
    hindi: { title: "आपका चेहरा राज़ छुपा रहा है", body: "{name}, छह लक्षण, सामुद्रिक शास्त्र के तरीके से पढ़े गए।" },
    telugu: { title: "మీ ముఖం రహస్యాలు దాస్తోంది", body: "{name}, ఆరు లక్షణాలు, సాముద్రిక శాస్త్రం చదివే విధంగా." },
    tamil: { title: "உங்கள் முகம் ரகசியம் வைத்துள்ளது", body: "{name}, ஆறு அம்சங்கள், சாமுத்ரிகா சாஸ்திரம் படிக்கும் முறையில்." },
    kannada: { title: "ನಿಮ್ಮ ಮುಖ ರಹಸ್ಯ ಇಟ್ಟುಕೊಂಡಿದೆ", body: "{name}, ಆರು ಲಕ್ಷಣಗಳು, ಸಾಮುದ್ರಿಕ ಶಾಸ್ತ್ರ ಓದುವ ರೀತಿಯಲ್ಲಿ." },
    malayalam: { title: "നിങ്ങളുടെ മുഖം രഹസ്യം സൂക്ഷിക്കുന്നു", body: "{name}, ആറ് ലക്ഷണങ്ങൾ, സാമുദ്രിക ശാസ്ത്രം വായിക്കുന്ന വിധത്തിൽ." },
  },
  face_new_1: {
    english: { title: "Look up for a moment 👁️", body: "Eyes, brow, jaw — your face says what your palm cannot. See what." },
    hinglish: { title: "Ek pal ke liye upar dekhiye 👁️", body: "Aankhein, bhauhein, jabda — chehra vo kehta hai jo haath nahi keh sakta." },
    hindi: { title: "एक पल के लिए ऊपर देखिए 👁️", body: "आंखें, भौंहें, जबड़ा — चेहरा वो कहता है जो हाथ नहीं कह सकता।" },
    telugu: { title: "ఒక్క క్షణం పైకి చూడండి 👁️", body: "కళ్ళు, కనుబొమ్మలు, దవడ — చెయ్యి చెప్పలేనిది ముఖం చెబుతుంది." },
    tamil: { title: "ஒரு கணம் நிமிர்ந்து பாருங்கள் 👁️", body: "கண்கள், புருவம், தாடை — கை சொல்ல முடியாததை முகம் சொல்கிறது." },
    kannada: { title: "ಒಂದು ಕ್ಷಣ ಮೇಲೆ ನೋಡಿ 👁️", body: "ಕಣ್ಣು, ಹುಬ್ಬು, ದವಡೆ — ಕೈ ಹೇಳಲಾಗದ್ದನ್ನು ಮುಖ ಹೇಳುತ್ತದೆ." },
    malayalam: { title: "ഒരു നിമിഷം മുകളിലേക്ക് നോക്കൂ 👁️", body: "കണ്ണ്, പുരികം, താടി — കൈ പറയാത്തത് മുഖം പറയും." },
  },
  face_ask_0: {
    english: { title: "Your face reading isn't finished", body: "{name}, ask Astro what your features say about the days ahead.", ask: "What does my face reading say about the days ahead?" },
    hinglish: { title: "Aapki face reading adhoori hai", body: "{name}, Astro se poochiye aapke lakshan aane wale dinon ke baare mein kya kehte hain.", ask: "Meri face reading aane wale dinon ke baare mein kya kehti hai?" },
    hindi: { title: "आपकी फेस रीडिंग अधूरी है", body: "{name}, Astro से पूछिए आपके लक्षण आने वाले दिनों के बारे में क्या कहते हैं।", ask: "मेरी फेस रीडिंग आने वाले दिनों के बारे में क्या कहती है?" },
    telugu: { title: "మీ ముఖ రీడింగ్ పూర్తి కాలేదు", body: "{name}, రాబోయే రోజుల గురించి మీ లక్షణాలు ఏమి చెబుతున్నాయో Astro ను అడగండి.", ask: "నా ముఖ రీడింగ్ రాబోయే రోజుల గురించి ఏమి చెబుతుంది?" },
    tamil: { title: "உங்கள் முக வாசிப்பு முடியவில்லை", body: "{name}, வரும் நாட்களைப் பற்றி உங்கள் அம்சங்கள் என்ன சொல்கின்றன என்று Astro-விடம் கேளுங்கள்.", ask: "என் முக வாசிப்பு வரும் நாட்களைப் பற்றி என்ன சொல்கிறது?" },
    kannada: { title: "ನಿಮ್ಮ ಮುಖ ರೀಡಿಂಗ್ ಮುಗಿದಿಲ್ಲ", body: "{name}, ಮುಂದಿನ ದಿನಗಳ ಬಗ್ಗೆ ನಿಮ್ಮ ಲಕ್ಷಣಗಳು ಏನು ಹೇಳುತ್ತವೆ ಎಂದು Astro ಅನ್ನು ಕೇಳಿ.", ask: "ನನ್ನ ಮುಖ ರೀಡಿಂಗ್ ಮುಂದಿನ ದಿನಗಳ ಬಗ್ಗೆ ಏನು ಹೇಳುತ್ತದೆ?" },
    malayalam: { title: "മുഖ വായന ഇനിയും തീർന്നിട്ടില്ല", body: "{name}, വരും ദിവസങ്ങളെക്കുറിച്ച് നിങ്ങളുടെ ലക്ഷണങ്ങൾ എന്ത് പറയുന്നു എന്ന് Astro-യോട് ചോദിക്കൂ.", ask: "എന്റെ മുഖ വായന വരും ദിവസങ്ങളെക്കുറിച്ച് എന്ത് പറയുന്നു?" },
  },
  face_ask_1: {
    english: { title: "What your face didn't tell you", body: "Astro read it once. Ask what it means for the question you're carrying.", ask: "What does my face reading mean for me right now?" },
    hinglish: { title: "Jo aapke chehre ne nahi bataya", body: "Astro ne ek baar padha hai. Poochiye vo aapke abhi ke sawaal ke liye kya maayne rakhta hai.", ask: "Meri face reading abhi mere liye kya maayne rakhti hai?" },
    hindi: { title: "जो आपके चेहरे ने नहीं बताया", body: "Astro ने एक बार पढ़ा है। पूछिए वो आपके अभी के सवाल के लिए क्या मायने रखता है।", ask: "मेरी फेस रीडिंग अभी मेरे लिए क्या मायने रखती है?" },
    telugu: { title: "మీ ముఖం చెప్పనిది", body: "Astro ఒకసారి చదివింది. మీ ప్రస్తుత ప్రశ్నకు అది ఏమి అర్థమో అడగండి.", ask: "నా ముఖ రీడింగ్ ఇప్పుడు నాకు ఏమి అర్థం?" },
    tamil: { title: "உங்கள் முகம் சொல்லாதது", body: "Astro ஒருமுறை படித்தது. உங்கள் இப்போதைய கேள்விக்கு அது என்ன அர்த்தம் என்று கேளுங்கள்.", ask: "என் முக வாசிப்பு இப்போது எனக்கு என்ன அர்த்தம்?" },
    kannada: { title: "ನಿಮ್ಮ ಮುಖ ಹೇಳದಿರುವುದು", body: "Astro ಒಮ್ಮೆ ಓದಿದೆ. ನಿಮ್ಮ ಈಗಿನ ಪ್ರಶ್ನೆಗೆ ಅದರ ಅರ್ಥವೇನು ಎಂದು ಕೇಳಿ.", ask: "ನನ್ನ ಮುಖ ರೀಡಿಂಗ್ ಈಗ ನನಗೆ ಏನು ಅರ್ಥ?" },
    malayalam: { title: "നിങ്ങളുടെ മുഖം പറയാത്തത്", body: "Astro ഒരിക്കൽ വായിച്ചു. നിങ്ങളുടെ ഇപ്പോഴത്തെ ചോദ്യത്തിന് അതെന്ത് അർത്ഥമെന്ന് ചോദിക്കൂ.", ask: "എന്റെ മുഖ വായന ഇപ്പോൾ എനിക്ക് എന്ത് അർത്ഥമാണ്?" },
  },

  // ---- 18:00, a question for Astro. ----
  chat_0: {
    english: { title: "One question before the day ends", body: "{name}, love, work or money — Astro answers with your own chart open.", ask: "What should I know about my life right now?" },
    hinglish: { title: "Din khatam hone se pehle ek sawaal", body: "{name}, pyaar, kaam ya paisa — Astro aapki hi kundali dekh kar jawaab deta hai.", ask: "Abhi meri zindagi ke baare mein mujhe kya jaanna chahiye?" },
    hindi: { title: "दिन ख़त्म होने से पहले एक सवाल", body: "{name}, प्यार, काम या पैसा — Astro आपकी ही कुंडली देखकर जवाब देता है।", ask: "अभी मेरी ज़िंदगी के बारे में मुझे क्या जानना चाहिए?" },
    telugu: { title: "రోజు ముగియక ముందు ఒక ప్రశ్న", body: "{name}, ప్రేమ, పని లేదా డబ్బు — Astro మీ జాతకం చూసే సమాధానం చెబుతుంది.", ask: "ఇప్పుడు నా జీవితం గురించి నేను ఏమి తెలుసుకోవాలి?" },
    tamil: { title: "நாள் முடிவதற்கு முன் ஒரு கேள்வி", body: "{name}, காதல், வேலை அல்லது பணம் — Astro உங்கள் ஜாதகத்தைப் பார்த்தே பதில் சொல்லும்.", ask: "இப்போது என் வாழ்க்கையைப் பற்றி நான் என்ன தெரிந்துகொள்ள வேண்டும்?" },
    kannada: { title: "ದಿನ ಮುಗಿಯುವ ಮೊದಲು ಒಂದು ಪ್ರಶ್ನೆ", body: "{name}, ಪ್ರೀತಿ, ಕೆಲಸ ಅಥವಾ ಹಣ — Astro ನಿಮ್ಮ ಜಾತಕ ನೋಡಿಯೇ ಉತ್ತರಿಸುತ್ತದೆ.", ask: "ಈಗ ನನ್ನ ಜೀವನದ ಬಗ್ಗೆ ನಾನು ಏನು ತಿಳಿಯಬೇಕು?" },
    malayalam: { title: "ദിവസം തീരും മുൻപ് ഒരു ചോദ്യം", body: "{name}, പ്രണയം, ജോലി അല്ലെങ്കിൽ പണം — Astro നിങ്ങളുടെ ജാതകം നോക്കിയാണ് ഉത്തരം പറയുക.", ask: "ഇപ്പോൾ എന്റെ ജീവിതത്തെക്കുറിച്ച് ഞാൻ എന്ത് അറിയണം?" },
  },
  chat_1: {
    english: { title: "Astro is still awake 🌗", body: "Ask the thing you have been turning over all day.", ask: "I have something on my mind — what do the stars say?" },
    hinglish: { title: "Astro abhi jaag raha hai 🌗", body: "Vo baat poochiye jo din bhar dimaag mein ghoom rahi hai.", ask: "Mere mann mein ek baat hai — sitare kya kehte hain?" },
    hindi: { title: "Astro अभी जाग रहा है 🌗", body: "वो बात पूछिए जो दिन भर दिमाग़ में घूम रही है।", ask: "मेरे मन में एक बात है — सितारे क्या कहते हैं?" },
    telugu: { title: "Astro ఇంకా మేల్కొని ఉంది 🌗", body: "రోజంతా మనసులో తిరుగుతున్న విషయం అడగండి.", ask: "నా మనసులో ఒక విషయం ఉంది — నక్షత్రాలు ఏమంటాయి?" },
    tamil: { title: "Astro இன்னும் விழித்திருக்கிறது 🌗", body: "நாள் முழுவதும் மனதில் சுற்றிய விஷயத்தைக் கேளுங்கள்.", ask: "என் மனதில் ஒன்று உள்ளது — நட்சத்திரங்கள் என்ன சொல்கின்றன?" },
    kannada: { title: "Astro ಇನ್ನೂ ಎಚ್ಚರವಾಗಿದೆ 🌗", body: "ದಿನವಿಡೀ ಮನಸ್ಸಲ್ಲಿ ಸುತ್ತಿದ ವಿಷಯವನ್ನು ಕೇಳಿ.", ask: "ನನ್ನ ಮನಸ್ಸಲ್ಲಿ ಒಂದು ವಿಷಯವಿದೆ — ನಕ್ಷತ್ರಗಳು ಏನು ಹೇಳುತ್ತವೆ?" },
    malayalam: { title: "Astro ഇപ്പോഴും ഉണർന്നിരിക്കുന്നു 🌗", body: "ദിവസം മുഴുവൻ മനസ്സിൽ കിടന്ന കാര്യം ചോദിക്കൂ.", ask: "എന്റെ മനസ്സിൽ ഒരു കാര്യമുണ്ട് — നക്ഷത്രങ്ങൾ എന്ത് പറയുന്നു?" },
  },

  // ---- 20:00, the close. `ask` names a planet from the reader's own kundali. ----
  evening_new_0: {
    english: { title: "Tomorrow is already moving", body: "{name}, the planets shift overnight. Ask Astro what you are walking into.", ask: "What does tomorrow hold for me?" },
    hinglish: { title: "Kal abhi se chalna shuru hai", body: "{name}, raat bhar grah apni jagah badalte hain. Astro se poochiye kal kya hai.", ask: "Kal mera din kaisa rahega?" },
    hindi: { title: "कल अभी से चलना शुरू है", body: "{name}, रात भर ग्रह अपनी जगह बदलते हैं। Astro से पूछिए कल क्या है।", ask: "कल मेरा दिन कैसा रहेगा?" },
    telugu: { title: "రేపు ఇప్పటికే కదులుతోంది", body: "{name}, రాత్రంతా గ్రహాలు స్థానం మారుతాయి. రేపు ఏముందో Astro ను అడగండి.", ask: "రేపు నా రోజు ఎలా ఉంటుంది?" },
    tamil: { title: "நாளை ஏற்கனவே நகர்கிறது", body: "{name}, இரவு முழுவதும் கிரகங்கள் இடம் மாறும். நாளை என்ன என்று Astro-விடம் கேளுங்கள்.", ask: "நாளை என் நாள் எப்படி இருக்கும்?" },
    kannada: { title: "ನಾಳೆ ಈಗಾಗಲೇ ಚಲಿಸುತ್ತಿದೆ", body: "{name}, ರಾತ್ರಿಯಿಡೀ ಗ್ರಹಗಳು ಸ್ಥಾನ ಬದಲಿಸುತ್ತವೆ. ನಾಳೆ ಏನೆಂದು Astro ಅನ್ನು ಕೇಳಿ.", ask: "ನಾಳೆ ನನ್ನ ದಿನ ಹೇಗಿರುತ್ತದೆ?" },
    malayalam: { title: "നാളെ ഇപ്പോഴേ നീങ്ങുന്നു", body: "{name}, രാത്രി മുഴുവൻ ഗ്രഹങ്ങൾ സ്ഥാനം മാറും. നാളെ എന്തെന്ന് Astro-യോട് ചോദിക്കൂ.", ask: "നാളെ എന്റെ ദിവസം എങ്ങനെയായിരിക്കും?" },
  },
  evening_ask_0: {
    english: { title: "{planet} is loud in your chart", body: "{name}, ask Astro what it has been quietly arranging for you.", ask: "What is {planet} doing in my chart right now?" },
    hinglish: { title: "Aapki kundali mein {planet} tez hai", body: "{name}, Astro se poochiye vo chupchaap aapke liye kya bana raha hai.", ask: "Abhi meri kundali mein {planet} kya kar raha hai?" },
    hindi: { title: "आपकी कुंडली में {planet} तेज़ है", body: "{name}, Astro से पूछिए वो चुपचाप आपके लिए क्या बना रहा है।", ask: "अभी मेरी कुंडली में {planet} क्या कर रहा है?" },
    telugu: { title: "మీ జాతకంలో {planet} బలంగా ఉంది", body: "{name}, అది మీ కోసం నిశ్శబ్దంగా ఏమి సిద్ధం చేస్తోందో Astro ను అడగండి.", ask: "ఇప్పుడు నా జాతకంలో {planet} ఏమి చేస్తోంది?" },
    tamil: { title: "உங்கள் ஜாதகத்தில் {planet} வலிமை", body: "{name}, அது உங்களுக்காக அமைதியாக என்ன செய்கிறது என்று Astro-விடம் கேளுங்கள்.", ask: "இப்போது என் ஜாதகத்தில் {planet} என்ன செய்கிறது?" },
    kannada: { title: "ನಿಮ್ಮ ಜಾತಕದಲ್ಲಿ {planet} ಪ್ರಬಲ", body: "{name}, ಅದು ನಿಮಗಾಗಿ ಸದ್ದಿಲ್ಲದೆ ಏನು ಮಾಡುತ್ತಿದೆ ಎಂದು Astro ಅನ್ನು ಕೇಳಿ.", ask: "ಈಗ ನನ್ನ ಜಾತಕದಲ್ಲಿ {planet} ಏನು ಮಾಡುತ್ತಿದೆ?" },
    malayalam: { title: "ജാതകത്തിൽ {planet} ശക്തമാണ്", body: "{name}, അത് നിങ്ങൾക്കായി നിശ്ശബ്ദം എന്ത് ഒരുക്കുന്നു എന്ന് Astro-യോട് ചോദിക്കൂ.", ask: "ഇപ്പോൾ എന്റെ ജാതകത്തിൽ {planet} എന്ത് ചെയ്യുന്നു?" },
  },

  // ---- locked: not entitled, so every tap lands on the paywall ----
  //
  // These exist because the twenty above would be lying. A `none` or `expired` account is the biggest
  // slice of the six-a-day track and `resolvePushNavigation` bounces it off `/palm`, `/face`, `/chat`
  // and `/kundali` — so "thirty seconds and eight lines" is a price tag four times a day, which is
  // the "make it sensible" rule broken on a schedule.
  //
  // Two of the six give the day's colour away for nothing. It is the one thing the app can hand
  // someone who has not paid, it costs nothing to give, and a push that delivers before it asks is
  // the only kind worth sending six times.
  //
  // No `ask`: these open `/subscribe`, where a seeded question has nowhere to go. Colour and planet
  // stay out of the titles, where Devanagari and Malayalam would eat the grapheme budget.
  locked_0: {
    english: { title: "Your colour for today 💫", body: "{name}, wear {colour} — that one is free. Unlock your chart to see the rest." },
    hinglish: { title: "Aaj ka aapka rang 💫", body: "{name}, {colour} pehniye — ye muft hai. Baaki dekhne ke liye apni kundali unlock karein." },
    hindi: { title: "आज का आपका रंग 💫", body: "{name}, {colour} पहनिए — ये मुफ़्त है। बाकी देखने के लिए अपनी कुंडली अनलॉक करें।" },
    telugu: { title: "ఈరోజు మీ రంగు 💫", body: "{name}, {colour} ధరించండి — ఇది ఉచితం. మిగతాది చూడటానికి మీ జాతకాన్ని అన్‌లాక్ చేయండి." },
    tamil: { title: "இன்றைய உங்கள் நிறம் 💫", body: "{name}, {colour} அணியுங்கள் — இது இலவசம். மீதியைக் காண உங்கள் ஜாதகத்தை அன்லாக் செய்யுங்கள்." },
    kannada: { title: "ಇಂದಿನ ನಿಮ್ಮ ಬಣ್ಣ 💫", body: "{name}, {colour} ಧರಿಸಿ — ಇದು ಉಚಿತ. ಉಳಿದದ್ದನ್ನು ನೋಡಲು ನಿಮ್ಮ ಜಾತಕ ಅನ್‌ಲಾಕ್ ಮಾಡಿ." },
    malayalam: { title: "ഇന്നത്തെ നിങ്ങളുടെ നിറം 💫", body: "{name}, {colour} ധരിക്കൂ — ഇത് സൗജന്യം. ബാക്കി കാണാൻ ജാതകം അൺലോക്ക് ചെയ്യൂ." },
  },
  locked_1: {
    english: { title: "The sky moved last night 🌙", body: "{planet} owns today. Unlock Astrolok to find out what that means for you." },
    hinglish: { title: "Raat bhar aasmaan badla 🌙", body: "Aaj {planet} ka din hai. Iska aapke liye kya matlab hai, Astrolok unlock karke jaaniye." },
    hindi: { title: "रात भर आसमान बदला 🌙", body: "आज {planet} का दिन है। इसका आपके लिए क्या मतलब है, Astrolok अनलॉक करके जानिए।" },
    telugu: { title: "రాత్రి ఆకాశం కదిలింది 🌙", body: "ఈరోజు {planet} ది. ఇది మీకు ఏమిటో తెలుసుకోవడానికి Astrolok అన్‌లాక్ చేయండి." },
    tamil: { title: "இரவில் வானம் நகர்ந்தது 🌙", body: "இன்று {planet} உடையது. இது உங்களுக்கு என்ன என்று அறிய Astrolok-ஐ அன்லாக் செய்யுங்கள்." },
    kannada: { title: "ರಾತ್ರಿ ಆಕಾಶ ಚಲಿಸಿತು 🌙", body: "ಇಂದು {planet} ದು. ಇದು ನಿಮಗೇನು ಎಂದು ತಿಳಿಯಲು Astrolok ಅನ್‌ಲಾಕ್ ಮಾಡಿ." },
    malayalam: { title: "രാത്രി ആകാശം നീങ്ങി 🌙", body: "ഇന്ന് {planet} ന്റേതാണ്. ഇത് നിങ്ങൾക്ക് എന്തെന്ന് അറിയാൻ Astrolok അൺലോക്ക് ചെയ്യൂ." },
  },
  locked_2: {
    english: { title: "Eight lines, six features, nine planets", body: "Your palm, your face, your chart. Unlock all three and Astro reads them for you." },
    hinglish: { title: "Aath lakeerein, chhe lakshan, nau grah", body: "Aapka haath, chehra, kundali. Teeno unlock kijiye aur Astro padhega." },
    hindi: { title: "आठ रेखाएं, छह लक्षण, नौ ग्रह", body: "आपका हाथ, चेहरा, कुंडली। तीनों अनलॉक कीजिए और Astro पढ़ेगा।" },
    telugu: { title: "ఎనిమిది రేఖలు, ఆరు లక్షణాలు, తొమ్మిది గ్రహాలు", body: "మీ చెయ్యి, ముఖం, జాతకం. మూడూ అన్‌లాక్ చేయండి, Astro చదువుతుంది." },
    tamil: { title: "எட்டு கோடுகள், ஆறு அம்சங்கள்", body: "உங்கள் கை, முகம், ஜாதகம். மூன்றையும் அன்லாக் செய்யுங்கள், Astro படிக்கும்." },
    kannada: { title: "ಎಂಟು ಗೆರೆ, ಆರು ಲಕ್ಷಣ, ಒಂಬತ್ತು ಗ್ರಹ", body: "ನಿಮ್ಮ ಕೈ, ಮುಖ, ಜಾತಕ. ಮೂರನ್ನೂ ಅನ್‌ಲಾಕ್ ಮಾಡಿ, Astro ಓದುತ್ತದೆ." },
    malayalam: { title: "എട്ട് രേഖ, ആറ് ലക്ഷണം, ഒൻപത് ഗ്രഹം", body: "നിങ്ങളുടെ കൈ, മുഖം, ജാതകം. മൂന്നും അൺലോക്ക് ചെയ്യൂ, Astro വായിക്കും." },
  },
  locked_3: {
    english: { title: "Astro is waiting to meet you", body: "{name}, one plan unlocks your palm, your face, your Kundali and every question." },
    hinglish: { title: "Astro aapse milne ka intezaar mein", body: "{name}, ek plan mein haath, chehra, Kundali aur har sawaal unlock ho jaata hai." },
    hindi: { title: "Astro आपसे मिलने का इंतज़ार में", body: "{name}, एक प्लान में हाथ, चेहरा, कुंडली और हर सवाल अनलॉक हो जाता है।" },
    telugu: { title: "Astro మిమ్మల్ని కలవాలని ఎదురుచూస్తోంది", body: "{name}, ఒక ప్లాన్‌తో చెయ్యి, ముఖం, జాతకం, ప్రతి ప్రశ్న అన్‌లాక్ అవుతాయి." },
    tamil: { title: "Astro உங்களைச் சந்திக்கக் காத்திருக்கிறது", body: "{name}, ஒரு திட்டத்தில் கை, முகம், ஜாதகம், ஒவ்வொரு கேள்வியும் அன்லாக்." },
    kannada: { title: "Astro ನಿಮ್ಮನ್ನು ಭೇಟಿಯಾಗಲು ಕಾಯುತ್ತಿದೆ", body: "{name}, ಒಂದು ಪ್ಲಾನ್‌ನಲ್ಲಿ ಕೈ, ಮುಖ, ಜಾತಕ ಮತ್ತು ಪ್ರತಿ ಪ್ರಶ್ನೆ ಅನ್‌ಲಾಕ್." },
    malayalam: { title: "Astro നിങ്ങളെ കാണാൻ കാത്തിരിക്കുന്നു", body: "{name}, ഒരു പ്ലാനിൽ കൈ, മുഖം, ജാതകം, എല്ലാ ചോദ്യവും അൺലോക്ക് ആകും." },
  },
  locked_4: {
    english: { title: "Something is written for you ✨", body: "It has been since the hour you were born. Unlock your chart and read it." },
    hinglish: { title: "Kuch aapke liye likha hai ✨", body: "Jis ghadi aap paida hue, tabhi se. Apni kundali unlock kijiye aur padhiye." },
    hindi: { title: "कुछ आपके लिए लिखा है ✨", body: "जिस घड़ी आप पैदा हुए, तभी से। अपनी कुंडली अनलॉक कीजिए और पढ़िए।" },
    telugu: { title: "మీ కోసం ఏదో రాసి ఉంది ✨", body: "మీరు పుట్టిన గడియ నుండే. మీ జాతకాన్ని అన్‌లాక్ చేసి చదవండి." },
    tamil: { title: "உங்களுக்காக ஏதோ எழுதப்பட்டுள்ளது ✨", body: "நீங்கள் பிறந்த நேரம் முதல். உங்கள் ஜாதகத்தை அன்லாக் செய்து படியுங்கள்." },
    kannada: { title: "ನಿಮಗಾಗಿ ಏನೋ ಬರೆದಿದೆ ✨", body: "ನೀವು ಹುಟ್ಟಿದ ಗಳಿಗೆಯಿಂದಲೇ. ನಿಮ್ಮ ಜಾತಕ ಅನ್‌ಲಾಕ್ ಮಾಡಿ ಓದಿ." },
    malayalam: { title: "നിങ്ങൾക്കായി എന്തോ എഴുതിയിട്ടുണ്ട് ✨", body: "നിങ്ങൾ ജനിച്ച നേരം മുതൽ. ജാതകം അൺലോക്ക് ചെയ്ത് വായിക്കൂ." },
  },
  locked_5: {
    english: { title: "Your stars kept your place", body: "{name}, wear {colour} today. When you're ready, unlock what else is waiting." },
    hinglish: { title: "Sitaron ne aapki jagah rakhi hai", body: "{name}, aaj {colour} pehniye. Taiyaar ho toh baaki bhi unlock kijiye." },
    hindi: { title: "सितारों ने आपकी जगह रखी है", body: "{name}, आज {colour} पहनिए। तैयार हों तो बाकी भी अनलॉक कीजिए।" },
    telugu: { title: "నక్షత్రాలు మీ స్థానం ఉంచాయి", body: "{name}, ఈరోజు {colour} ధరించండి. సిద్ధమైనప్పుడు మిగతాది అన్‌లాక్ చేయండి." },
    tamil: { title: "நட்சத்திரங்கள் உங்கள் இடத்தை வைத்துள்ளன", body: "{name}, இன்று {colour} அணியுங்கள். தயாராகும்போது மீதியை அன்லாக் செய்யுங்கள்." },
    kannada: { title: "ನಕ್ಷತ್ರಗಳು ನಿಮ್ಮ ಜಾಗ ಇಟ್ಟಿವೆ", body: "{name}, ಇಂದು {colour} ಧರಿಸಿ. ಸಿದ್ಧವಾದಾಗ ಉಳಿದದ್ದನ್ನು ಅನ್‌ಲಾಕ್ ಮಾಡಿ." },
    malayalam: { title: "നക്ഷത്രങ്ങൾ നിങ്ങളുടെ ഇടം സൂക്ഷിച്ചു", body: "{name}, ഇന്ന് {colour} ധരിക്കൂ. തയ്യാറാകുമ്പോൾ ബാക്കിയും അൺലോക്ക് ചെയ്യൂ." },
  },
};

// ---------------------------------------------------------------- pools

/**
 * Which variants a (slot, state) may draw from. The single source of truth for pool sizes: SQL hands
 * over a raw hash and [dripVariantFor] does the modulo, so nothing here has to agree with a migration.
 *
 * `today` and `chat` have no second state of their own — there is nothing to have already done about
 * today, or about being asked a question — so they carry only `new` and [dripVariantFor] falls back
 * to it if anything ever asks them for `ask`.
 */
export const DRIP_POOLS: Record<DripSlot, Partial<Record<DripState, readonly DripVariantKey[]>>> = {
  today: { new: ["today_0", "today_1", "today_2", "today_3"] },
  palm: { new: ["palm_new_0", "palm_new_1"], ask: ["palm_ask_0", "palm_ask_1"] },
  kundali: { new: ["kundali_new_0", "kundali_new_1"], ask: ["kundali_ask_0", "kundali_ask_1"] },
  face: { new: ["face_new_0", "face_new_1"], ask: ["face_ask_0", "face_ask_1"] },
  chat: { new: ["chat_0", "chat_1"] },
  evening: { new: ["evening_new_0"], ask: ["evening_ask_0"] },
};

/** Shared by every slot when the reader is not entitled. */
export const LOCKED_POOL = ["locked_0", "locked_1", "locked_2", "locked_3", "locked_4", "locked_5"] as const;

/**
 * The variant for one (slot, state, hash). Total by construction: any integer picks a real variant,
 * because `drip_variant()` is a hash and a hash is not something to trust the range of.
 */
export function dripVariantFor(slot: DripSlot, state: DripState, pick: number): DripVariantKey {
  const pool = state === "locked" ? LOCKED_POOL : (DRIP_POOLS[slot][state] ?? DRIP_POOLS[slot].new!);
  const index = Number.isFinite(pick) ? Math.abs(Math.trunc(pick)) % pool.length : 0;
  return pool[index];
}

/**
 * Which state draws this variant — the inverse of [dripVariantFor], from the pools themselves rather
 * than from the variant's spelling. `send_test` uses it to route a variant an operator named by hand.
 */
export function dripStateOf(variant: DripVariantKey): DripState {
  if ((LOCKED_POOL as readonly string[]).includes(variant)) return "locked";
  for (const states of Object.values(DRIP_POOLS)) {
    for (const [state, pool] of Object.entries(states)) {
      if ((pool ?? []).includes(variant)) return state as DripState;
    }
  }
  return "new";
}

// ---------------------------------------------------------------- rendering

/**
 * Capitalises every sentence start, because a placeholder can land on one.
 *
 * `fill` already handles the case where it has taken a `{name}` off the front, but `{colour}` is a
 * plain noun — "red", "laal" — and it sits wherever the sentence needs it. Both of these were going
 * out lower-case before this existed:
 *
 *   "red is your colour for luck today."            (`today_1`, opening the string)
 *   "…kalam Shani ke haath mein hai. laal pehniye"  (`today_3`, opening the second sentence)
 *
 * A no-op for the five Indic scripts, which have no case, and for `{planet}` and `{name}`, which are
 * capitalised in their own tables.
 */
function sentenceCase(text: string): string {
  return text.replace(
    /(^|[.!?।]\s+)(\p{Ll})/gu,
    (_, lead: string, letter: string) => lead + letter.toUpperCase(),
  );
}

/**
 * The title, body and seeded question for one drip variant, in one language.
 *
 * `{colour}` and `{planet}` are filled from the IST weekday — except that `planet` overrides the
 * weekday's lord, which is how the evening push names a graha out of the reader's own chart rather
 * than the one that happens to own the day. Unknown planet keys fall back to the weekday's lord, so a
 * stale or malformed param costs the personalisation, not the push.
 */
export function renderDripCopy(
  variant: DripVariantKey,
  language: string | null | undefined,
  { name, now, planet }: { name?: string | null; now: Date; planet?: string | null },
): DripCopy & { language: CopyLanguage } {
  const wanted = (language ?? "").trim().toLowerCase() as CopyLanguage;
  const resolved: CopyLanguage = (COPY_LANGUAGES as readonly string[]).includes(wanted) ? wanted : "english";

  const template = DRIP_COPY[variant][resolved];
  const day = luckyDay(resolved, now);
  const named = PLANET_NAMES[resolved][(planet ?? "").trim().toLowerCase()];

  const first = nameFor(name);
  const write = (text: string) =>
    sentenceCase(
      fill(text.replaceAll("{colour}", day.colour).replaceAll("{planet}", named ?? day.planet), first),
    );

  return {
    title: write(template.title),
    body: write(template.body),
    ask: template.ask ? write(template.ask) : undefined,
    language: resolved,
  };
}
