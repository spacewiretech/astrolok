/**
 * What a chip is about, read from its words — so a shaadi answer never offers "Naukri kab pakki
 * hogi?".
 *
 * The prompt asks for follow-ups on the reply's own topic and mostly gets them; this is the floor
 * under it. A chip is dropped only when its words are clearly about another subject. A chip with
 * no subject words at all ("Upay kaise karun?", "Kaunsa mahina sabse accha?") is never dropped.
 *
 * Whole words in Roman letters, so "ex" is not "exam". Word starts in the Indian scripts, which
 * fuse endings on (ಮದುವೆಯ, திருமணத்தை, పెళ్లికి, पैसों) — with `(?!\p{M})` where a vowel sign
 * would turn the stem into another word: ಹಣ money, ಹಣೆ forehead; பண money, பணி work.
 */

import type { ReplyTopic } from "./astro_chat_v5.ts";

export type ChipTopic = Exclude<ReplyTopic, "general">;

const EDGE = "(?<![\\p{L}\\p{M}])";
const END = "(?![\\p{L}\\p{M}])";

/** Whole words, in any script. */
const words = (...alternatives: string[]) => `${EDGE}(?:${alternatives.join("|")})${END}`;

/** Word starts, for scripts that fuse their endings on. */
const stems = (...alternatives: string[]) => `${EDGE}(?:${alternatives.join("|")})`;

/** Nukta off, so ज़मीन and जमीन, typed either way, are one word. */
function fold(value: string): string {
  return value.normalize("NFC").replace(/\u093C/g, "");
}

/** "Rishta" and "partner" belong to both marriage and love — a business partner to neither. */
const BOTH_M_L_LATIN = [
  "(?<!business )partners?",
  "rish?t(?:a|aa|e|ey|on|o)",
  "relationship",
];

const TOPIC_WORDS: Record<ChipTopic, string[]> = {
  marriage: [
    words(
      "sh(?:a|aa)dd?(?:i|ee|iyan|iyaan|iyon)",
      "saadi",
      "marr(?:y|ied|iage|iages|ying)",
      "wedding",
      "viv(?:a|aa)h",
      "vaivahik",
      "b(?:y|iy)aa?h",
      "j(?:ee|i)van ?s(?:a|aa)th(?:i|ee)",
      "life ?partner",
      "spouse",
      "husband",
      "wife",
      "pati",
      "patni",
      "b(?:i|ee)wi",
      "dulh(?:a|aa|an|in)",
      "bride",
      "groom",
      "sasural",
      "in-?laws",
      "saga(?:a)?i",
      "mangni",
      "engage(?:ment|d)",
      "arranged?",
      "kund(?:a)?l(?:i|ee) milan",
      "gun milan",
      // The one they will marry, the way a chip names them: "Ladki kya kaam karti hogi?", "Meri
      // hone wali kaisi hogi?" — so a question about the partner's work stays a marriage chip.
      "la(?:d|r)k(?:a|aa|i|ee|e|on|iyan|iyaan|iyon)",
      "(?:meri|mera|mere) hone ?wa(?:la|li|le)",
      "hone ?wa(?:la|li|le)(?= (?:ka|ki|ke|ko|se|kaisa|kaisi|kaise|kaun|kon)(?![\\p{L}\\p{M}]))",
      "fianc(?:e|ee|é|ée)",
      "damaa?d",
      "bahu",
      ...BOTH_M_L_LATIN,
      // Devanagari (Hindi, Marathi)
      "पति",
      "पत्नी",
      "नवरा",
      "बायको",
      "बहू",
      "सून",
      "जावई",
    ),
    stems(
      "शादी",
      "शादि",
      "विवाह",
      "वैवाहिक",
      "ब्याह",
      "जीवनसाथी",
      "जीवन साथी",
      "दूल्हा",
      "दुल्हा",
      "दुल्हन",
      "सगाई",
      "ससुराल",
      "अरेंज",
      "रिश्त",
      "लग्न",
      "जोडीदार",
      "कुंडली मिलान",
      "गुण मिलान",
      // लड़का, लड़की, once the nukta is folded off; मुलगा, मुलगी in Marathi.
      "लडक",
      "मुलग",
      "(?:मेरी|मेरा|मेरे) होने वा(?:ला|ली|ले)",
      "होने वा(?:ला|ली|ले)(?= (?:का|की|के|को|से|कैसा|कैसी|कैसे|कौन)(?![\\p{L}\\p{M}]))",
      "दामाद",
      "वधू",
      // Not पार्टनरशिप or बिज़नेस में पार्टनर, which are a business.
      "(?<!बिजनेस (?:में )?)पार्टनर(?!शिप)",
      // Kannada
      "ಮದುವೆ",
      "ಮದುವ",
      "ವಿವಾಹ",
      "ವೈವಾಹಿಕ",
      "ಕಲ್ಯಾಣ",
      "ಗಂಡ(?:ನ|ನು|ನಿಗೆ)?(?![\\p{L}\\p{M}])",
      "ಹೆಂಡತಿ",
      "ಪತ್ನಿ",
      "ಪತಿ(?![\\p{L}\\p{M}])",
      "ಸಂಗಾತಿ",
      "ಹೊಂದಾಣಿಕೆ",
      "ಅರೇಂಜ್",
      // ಹುಡುಗ, ಹುಡುಗಿ: "ಹುಡುಗಿ ಉದ್ಯೋಗ ಮಾಡುತ್ತಾರಾ?" is about the bride, not their own job.
      "ಹುಡುಗ",
      "ಮದುಮಗ",
      "ವಧು",
      "ಅಳಿಯ",
      "ಸೊಸೆ",
      // Tamil
      "திருமண",
      "கல்யாண",
      "கணவ(?:ன்|ர்|ரு|னு|னி|னை)",
      "மனைவி",
      "வாழ்க்கைத் துணை",
      "வாழ்க்கை துணை",
      "வரன்",
      "மாப்பிள்ளை",
      "பெண்",
      "மணமக",
      "மருமக",
      // Telugu
      "పెళ్లి",
      "పెళ్ళి",
      "పెళ్ల",
      "వివాహ",
      "వైవాహిక",
      "కల్యాణ",
      "కళ్యాణ",
      "భర్త",
      "భార్య",
      "భాగస్వామి",
      "సంబంధ",
      "అబ్బాయి",
      "అమ్మాయి",
      "వధువ",
      "వరుడ",
      "అల్లుడ",
      "కోడల",
      // Malayalam
      "വിവാഹ",
      "കല്യാണ",
      "ഭ(?:ർ|ര്)ത്താ",
      "ഭാര്യ",
      "ജീവിതപങ്കാളി",
      "ജീവിത പങ്കാളി",
      "പങ്കാളി",
      "ദാമ്പത്യ",
      "അറേഞ്ച്",
      "വധു",
      // വരൻ, the groom — never the stem, which is വരും ("will come") and വരുമാനം (income).
      "വര(?:ൻ|ന്റ)",
      "പെണ്ണ",
      "ചെറുക്ക",
    ),
  ],

  love: [
    words(
      "love",
      "lovers?",
      "p(?:y|iy|i)aa?r",
      "prem",
      "ishq",
      "m(?:o|u)habb?at",
      "ex",
      "ex-?(?:bf|gf|boyfriend|girlfriend)",
      "break ?-?up",
      "boy ?friend",
      "girl ?friend",
      "bf",
      "gf",
      "crush",
      "patch ?-?up",
      "unblock",
      "block(?:ed)?",
      "dhokh?a",
      "cheat(?:ing|ed)?",
      "(?:wa|va)a?pas aa?y?e?g(?:a|i|e)",
      "(?:call|message|msg|baat) kar(?:ega|egi)",
      // The one they love, by what they fear of them: "kya wo kisi aur se baat kar raha hai?" —
      // the craft's own example, which read as no subject at all — and talking again.
      "kisi aur (?:se|ke|ki|ko)",
      "(?:phir se|fir se|dobara|dubara) (?:\\S+ ){0,2}(?:baat|call|message|msg)",
      ...BOTH_M_L_LATIN,
      // Devanagari
      "लव",
      "लव्ह",
      "एक्स",
    ),
    stems(
      "प्यार",
      "प्रेम",
      "इश्क",
      "मोहब्बत",
      "ब्रेकअप",
      "बॉयफ्रेंड",
      "गर्लफ्रेंड",
      "रिश्त",
      "वापस आए",
      "वापस आये",
      "किसी और (?:से|के|की|को)",
      "(?:फिर से|दोबारा) (?:\\S+ ){0,2}(?:बात|कॉल|मैसेज)",
      // Talking again, in the southern languages: "அவர் மீண்டும் என்னிடம் பேசுவாரா?", "ಅವನು ಮತ್ತೆ
      // ನನ್ನ ಜೊತೆ ಮಾತಾಡ್ತಾನಾ?" — each read as no subject, and asked to choose one.
      "(?:ಮತ್ತೆ|ವಾಪಸ್) (?:\\S+ ){0,2}ಮಾತ",
      "(?:மீண்டும்|திரும்ப(?:வும்)?) (?:\\S+ ){0,2}பேசு",
      "(?:మళ్ళీ|మళ్లీ|తిరిగి) (?:\\S+ ){0,2}మాట్లాడ",
      "(?:വീണ്ടും|തിരിച്ച്) (?:\\S+ ){0,2}സംസാരിക്ക",
      // Kannada
      "ಪ್ರೀತಿ",
      "ಪ್ರೇಮ",
      "ಲವ್",
      "ಬ್ರೇಕಪ್",
      "ಹೊಂದಾಣಿಕೆ",
      // Tamil
      "காதல",
      "லவ்",
      "பிரேக்கப்",
      "பிரேக் அப்",
      // Telugu
      "ప్రేమ",
      "లవ్",
      "బ్రేకప్",
      "సంబంధ",
      // Malayalam
      "പ്രണയ",
      "പ്രേമ",
      "ലവ്",
      "ബ്രേക്കപ്പ",
      "പങ്കാളി",
    ),
  ],

  children: [
    words(
      "ba(?:cch|chch|chh)(?:a|aa|e|i|on|o|ey)",
      "santaa?n",
      "santana",
      "santati",
      "aula?a?d",
      "child(?:ren)?",
      "kids?",
      "pregnan(?:cy|t)",
      "conceiv(?:e|ing)",
      "putra",
      "second (?:child|baby)",
    ),
    stems(
      "बच्च",
      "संतान",
      "सन्तान",
      "संतत",
      "औलाद",
      "गर्भ",
      "प्रेगनेंसी",
      "पुत्र",
      "अपत्य",
      "बाळ",
      // Kannada
      "ಮಗು",
      "ಮಕ್ಕಳ",
      "ಸಂತಾನ",
      // Tamil
      "குழந்தை",
      "பிள்ளை",
      "சந்தான",
      "வாரிசு",
      // Telugu
      "పిల్లల",
      "పిల్లలు",
      "సంతాన",
      "బిడ్డ",
      // Malayalam
      "കുഞ്ഞ",
      "കുട്ടി",
      "സന്താന",
      "മക്ക(?:ൾ|ള്)",
    ),
  ],

  career: [
    words(
      "jobs?",
      "n(?:a|o)u?ka?ri(?:yan|yaan|yon)?",
      "careers?",
      "carr?ier",
      "promot(?:ion|ed)",
      "office",
      "boss",
      "interviews?",
      "sarkari",
      "govt",
      "government",
      "business",
      "bi(?:j|z)ness",
      "vy(?:a|aa)p(?:a|aa)r",
      "vyava?s(?:a|aa)y",
      "dhandh?(?:a|e)",
      "transfer",
      "salary",
      // A raise is on the career menu, in whatever word they use for pay.
      "vetan",
      "tan(?:a)?kh(?:w)?aa?h?",
      "company",
      "startup",
      "profession(?:al)?",
      "tara(?:kk|qq|k)i",
      "field",
      // "Upay kaam karega?" asks whether the upay works, not about work.
      "kaam(?![\\p{L}\\p{M}])(?!\\s+kar)",
      // English's "work" the same way: "What of my work?" is work, "Will the remedy work?",
      // "How does Ashlesha work?" and "Will it work out?" are not — the commonest English chips
      // under v4's love and marriage answers were the first kind.
      "(?<!(?:remed(?:y|ies)|upaa?y|mantra|puja|it|this|that|how does(?: my)? \\S+) )" +
      "work(?:s|ing|place)?(?! out)(?!s? for me)",
      "(?:un)?employ(?:ment|ed|er|ers)",
      "colleagues?",
      // Going abroad is on the work menu ("work abroad"): "videsh mein settle ho paunga?" read as
      // no subject, and was asked "shaadi, naukri ya paisa?".
      "vid(?:e|ae|ai)sh",
      "pardes",
      "abroad",
      "foreign",
      "overseas",
      "(?:bahar|baahar) (?:ke )?(?:desh|mulk)",
      // Devanagari
      "काम(?![\\p{L}\\p{M}])(?!\\s+कर)",
    ),
    stems(
      "नौकरी",
      "नोकरी",
      "करियर",
      "कैरियर",
      "करिअर",
      "व्यापार",
      "व्यवसाय",
      "बिजनेस",
      "प्रमोशन",
      "सरकारी",
      "जॉब",
      "इंटरव्यू",
      "ऑफिस",
      "धंध",
      "तरक्की",
      "पदोन्नति",
      "कारोबार",
      "बढती",
      "विदेश",
      "परदेश",
      "ವಿದೇಶ",
      "வெளிநாட",
      "విదేశ",
      "വിദേശ",
      // Pay belongs to both work and money, in the loan-word and in each language's own: a raise
      // is on the career menu. तनख़्वाह once the nukta is folded off.
      "सैलरी",
      "वेतन",
      "तनख्व",
      "तनखा",
      "ಸಂಬಳ",
      "ವೇತನ",
      "சம்பள",
      "ஊதிய",
      "జీత",
      "వేతన",
      "ശമ്പള",
      "വേതന",
      // Kannada
      "ಉದ್ಯೋಗ",
      "ಕೆಲಸ",
      "ವೃತ್ತಿ",
      "ನೌಕರಿ",
      "ಬಿಸಿನೆಸ್",
      "ವ್ಯಾಪಾರ",
      "ವ್ಯವಹಾರ",
      "ಜಾಬ್",
      "ಸರ್ಕಾರಿ",
      "ಕರಿಯರ್",
      "ಪ್ರಮೋಷನ್",
      "ಬಡ್ತಿ",
      // Tamil
      "வேலை",
      "தொழில",
      "உத்தியோக",
      "பதவி உயர்வு",
      "வியாபார",
      "பிசினஸ்",
      "கேரியர்",
      // Telugu
      "ఉద్యోగ",
      "కెరీర్",
      "వ్యాపార",
      "బిజినెస్",
      "జాబ్",
      "ప్రమోషన్",
      "వృత్తి",
      // Malayalam
      "ജോലി",
      "തൊഴി(?:ൽ|ല്)",
      "ഉദ്യോഗ",
      "ബിസിനസ",
      "കരിയ(?:ർ|ര്)",
      "പ്രമോഷ(?:ൻ|ന്)",
      "വ്യാപാര",
      "സ(?:ർ|ര്)ക്കാ(?:ർ|ര്) ജോലി",
    ),
  ],

  money: [
    words(
      "pa(?:i|y)?s(?:a|aa|e|on|o)",
      "money",
      "dhan",
      "wealth",
      "income",
      "kamaa?i",
      "aa?mdani",
      "profit",
      "mun(?:a|aa)fa",
      "nu(?:k|q)saa?n",
      "loss",
      "la(?:k|x)shmi",
      "laxmi",
      "financ(?:e|es|ial)",
      "aa?rthik",
      "invest(?:ment|ments)?",
      "stocks?",
      "share ?market",
      "trading",
      "lottery",
      "am(?:ee|i)r",
      "rich",
      "savings?",
      "bachat",
      "salary",
      "vetan",
      "tan(?:a)?kh(?:w)?aa?h?",
      // Devanagari
      "धन",
      "आय",
    ),
    stems(
      "पैस",
      "पैश",
      "आर्थिक",
      "कमाई",
      "आमदनी",
      "मुनाफा",
      "नुकसान",
      "लक्ष्मी",
      "अमीर",
      "बचत",
      "निवेश",
      "सैलरी",
      "वेतन",
      "तनख्व",
      "तनखा",
      "संपत्ति",
      // Kannada
      "ಹಣ(?!\\p{M})",
      "ಧನ(?!\\p{M})",
      "ಆರ್ಥಿಕ",
      "ಸಂಪತ್ತ",
      "ಉಳಿತಾಯ",
      "ಆದಾಯ",
      "ಸಂಬಳ",
      "ವೇತನ",
      // Tamil
      "பண(?!\\p{M})",
      "செல்வ",
      "பொருளாதார",
      "வருமான",
      "சம்பள",
      "ஊதிய",
      "சேமிப்ப",
      // Telugu
      "డబ్బ",
      "ధన(?!\\p{M})",
      "ఆర్థిక",
      "సంపాద",
      "ఆదాయ",
      "సంపద",
      "జీత",
      "వేతన",
      "పొదుప",
      // Malayalam
      "പണ(?!\\p{M})",
      "ധന(?!\\p{M})",
      "സാമ്പത്തിക",
      "വരുമാന",
      "സമ്പത്ത",
      "സമ്പാദ്യ",
      "ശമ്പള",
      "വേതന",
    ),
  ],

  debt: [
    words(
      "ka?r(?:z|j)(?:a|aa)?",
      "q(?:a)?rz(?:a)?",
      "kar(?:z|j)on",
      "loans?",
      "debts?",
      "udhaar(?:i)?",
      "udhari",
      "emis?",
      "rin",
      "rin mochan",
    ),
    stems(
      "कर्ज",
      "क़र्ज",
      "ऋण",
      "उधार",
      "लोन",
      "ईएमआई",
      // Kannada
      "ಸಾಲ(?!\\p{M})",
      "ಋಣ",
      "ಲೋನ್",
      // Tamil
      "கடன",
      "லோன்",
      // Telugu
      "అప్పు",
      "అప్పుల",
      "రుణ",
      "లోన్",
      // Malayalam
      "കട(?:ം|ത്ത|ബാധ|ക്കെണി|ങ്ങ)",
      "ലോ(?:ൺ|ണ്)",
    ),
  ],

  home: [
    words(
      "makaa?n",
      "house",
      "flats?",
      "propert(?:y|ies)",
      "z(?:a|aa)m(?:ee|i)n",
      "j(?:a|aa)m(?:ee|i)n",
      "plots?",
      "apartment",
      "real estate",
      "gr(?:i|u)?ha? ?pravesh",
      "home loan",
      // "Ghar", alone, is as often the family as the house: "ghar wale maanenge?"
      "(?:naya|nayaa|apna|apnaa|khud ka|khudka|own|new|dream) (?:ghar|house|home)",
      "ghar (?:kab|ka yog|ke yog|kh(?:a|aa)ree?d\\w*|khar(?:i|ee)d\\w*|ban\\w*|le(?:na|nge|nga|ga|gi)?)",
      "buy(?:ing)? (?:a )?(?:house|home|flat)",
    ),
    stems(
      "मकान",
      "प्रॉपर्टी",
      "प्रोपर्टी",
      "जमीन",
      "प्लॉट",
      "फ्लैट",
      "गृह प्रवेश",
      "होम लोन",
      "(?:नया|नए|अपना|अपने|खुद का|स्वतःचे|स्वतःचं) घर",
      "घर (?:कब|कधी|का योग|के योग|खरीद|बन|बांध|घे|ले)",
      // Kannada — ಮನೆಯವರು is the family
      "ಸ್ವಂತ ಮನೆ",
      "ಹೊಸ ಮನೆ",
      "ಮನೆ (?:ಕಟ್ಟ|ಖರೀದ|ಯೋಗ|ಯಾವಾಗ)",
      "ಆಸ್ತಿ",
      "ಸೈಟ್",
      "ಜಮೀನ",
      "ಫ್ಲಾಟ್",
      "ನಿವೇಶನ",
      // Tamil — வீட்டில் is at home, with the family
      "சொந்த வீ",
      "புது வீ",
      "புதிய வீ",
      "வீடு (?:கட்ட|வாங்க|எப்போது)",
      "சொத்து",
      "நிலம்",
      "மனை(?![\\p{L}\\p{M}])",
      // Telugu — ఇంటి వాళ్ళు is the family
      "సొంత ఇల్లు",
      "సొంతిల్లు",
      "కొత్త ఇల్లు",
      "ఇల్లు (?:కట్ట|కొన|ఎప్పుడు)",
      "ఆస్తి",
      "స్థల",
      "ఫ్లాట్",
      // Malayalam — വീട്ടുകാർ is the family
      "സ്വന്തം വീട",
      "പുതിയ വീട",
      "വീട് (?:പണി|വാങ്ങ|എപ്പോ)",
      "ഫ്ലാറ്റ",
      "വസ്തു",
    ),
  ],

  studies: [
    words(
      "padh?aa?i",
      "parhai",
      "stud(?:y|ies|ying)",
      "exams?",
      "par(?:i|ee)ksha",
      "preeksha",
      "college",
      "school",
      "admission",
      "marks",
      "neet",
      "upsc",
      "ssc",
      "education",
      "degree",
      "competitive",
      "coaching",
      "topper",
    ),
    stems(
      "पढाई",
      "परीक्ष",
      "एग्जाम",
      "कॉलेज",
      "स्कूल",
      "शिक्षा",
      "शिक्षण",
      "एडमिशन",
      "डिग्री",
      "अभ्यास",
      // Kannada
      "ಶಿಕ್ಷಣ",
      "ಪರೀಕ್ಷ",
      "ವಿದ್ಯಾಭ್ಯಾಸ",
      "ಕಾಲೇಜ",
      "ಎಕ್ಸಾಮ",
      "ಓದಿನ",
      // Tamil
      "படிப்ப",
      "தேர்வ",
      "கல்வி",
      "கல்லூரி",
      "பரீட்சை",
      // Telugu
      "చదువ",
      "పరీక్ష",
      "విద్య",
      "కాలేజ",
      "ఎగ్జామ",
      // Malayalam
      "പഠന",
      "പഠിപ്പ",
      "പരീക്ഷ",
      "വിദ്യാഭ്യാസ",
      "കോളേജ",
    ),
  ],

  health: [
    words(
      "health",
      "seh(?:a|e)t",
      // Sick as well as sickness, and the everyday word for how someone is keeping.
      "b(?:i|ee)maa?r(?:i|ee)?",
      "tab(?:i|ee)y?(?:a|e)t",
      "illness",
      "disease",
      "operation",
      "surgery",
      "hospital",
      "ilaa?j",
      "treatment",
      "recovery",
      // "Doctor se salah ka sahi samay?" is medical timing, which v5 does not give.
      "doctors?",
    ),
    stems(
      "सेहत",
      "स्वास्थ्य",
      "बीमार",
      "तबीयत",
      "तबियत",
      "इलाज",
      "ऑपरेशन",
      "अस्पताल",
      "रोग",
      "डॉक्टर",
      "ಡಾಕ್ಟರ",
      "மருத்துவ",
      "డాక్టర",
      "ഡോക്ട",
      "ಆರೋಗ್ಯ",
      "ಕಾಯಿಲೆ",
      "உடல்நல",
      "ஆரோக்கிய",
      "நோய்",
      "ఆరోగ్య",
      "అనారోగ్య",
      "వ్యాధి",
      "ആരോഗ്യ",
      "രോഗ",
      "അസുഖ",
    ),
  ],
};

const PATTERNS: ReadonlyArray<readonly [ChipTopic, RegExp]> = (
  Object.entries(TOPIC_WORDS) as Array<[ChipTopic, string[]]>
).map(([topic, parts]) => [topic, new RegExp(fold(parts.join("|")), "iu")] as const);

/** Every subject [value] names, in any of the languages. Empty for a chip with no subject. */
export function topicsOf(value: string): Set<ChipTopic> {
  const said = fold(value).toLowerCase().replace(/\s+/g, " ");
  const found = new Set<ChipTopic>();
  for (const [topic, pattern] of PATTERNS) if (pattern.test(said)) found.add(topic);
  return found;
}

/**
 * What a follow-up under a reply on [topic] may be about. Love and marriage lead into each other;
 * studies and work do; money and debt do. Nothing else crosses. Not listed — general — takes any
 * subject but health.
 */
const ALLOWED: Partial<Record<ReplyTopic, ReadonlyArray<ChipTopic>>> = {
  marriage: ["marriage", "love"],
  love: ["love", "marriage"],
  children: ["children"],
  career: ["career", "studies"],
  money: ["money", "debt"],
  debt: ["debt", "money"],
  home: ["home"],
  studies: ["studies", "career"],
};

/**
 * "Them", as a chip names the partner: "Unka profession kaisa hoga?", "ಅವರ ವೃತ್ತಿ ಹೇಗಿರಬಹುದು?",
 * "அவர் என்ன வேலை செய்வார்?". Under a marriage or love answer that is the one they will marry or
 * the one they asked about, so a question about their work is still on the topic — these were
 * nearly every chip the guard dropped wrongly on v4's replies. Not "uske baad", which is "after
 * that".
 */
const PARTNER = new RegExp(
  fold(
    words(
      "us(?:ka|ki|ke|ko|se)(?! ba?a?d(?![\\p{L}\\p{M}]))",
      "un(?:ka|ki|ke|ko|se|he|hen|hone)",
      "they|their|them|he|she|his|her|him",
      "उस(?:का|की|के|को|से)(?! बाद(?![\\p{L}\\p{M}]))",
      "उन(?:का|की|के|को|से|्हें|्होंने)",
      "त्या(?:चं|चा|ची|चे|ला|च्या)",
      "ति(?:चं|चा|ची|चे|ला|च्या)",
      "त्यांच(?:ं|ा|ी|े|्या)",
    ) + "|" +
      stems(
        "ಅವರ",
        "ಅವನ",
        "ಅವಳ",
        "அவர",
        "அவன",
        "அவள",
        "ఆయన",
        "ఆమె",
        "అతని",
        "అతను",
        "അവന",
        "അവള",
        "അവര",
        "അയാള",
      ),
  ),
  "iu",
);

/**
 * Whether [option] is clearly about something other than [topic]. A chip naming two subjects stays
 * when one of them fits ("Shaadi ke baad naukri?" under marriage), and so does a chip about the
 * partner under marriage or love ([PARTNER]). Health is never a chip: v5 does not read it.
 */
export function offTopic(option: string, topic: ReplyTopic): boolean {
  const named = topicsOf(option);
  if (named.has("health")) return true;
  const allowed = ALLOWED[topic];
  if (!allowed || named.size === 0) return false;
  if (allowed.includes("marriage") && PARTNER.test(fold(option).replace(/\s+/g, " "))) return false;
  return ![...named].some((subject) => allowed.includes(subject));
}

/**
 * Two or three follow-ups per topic in each language, for when the model's own were off the
 * subject or already asked. The first person, three to six words, each naming its topic so
 * [offTopic] passes it. The southern-language and Marathi lines still want a native speaker's
 * read.
 */
const FALLBACK: Record<string, Partial<Record<ReplyTopic, string[]>>> = {
  hinglish: {
    marriage: ["Jeevansathi kaisa hoga?", "Love ya arrange?", "Shaadi mein deri kyun?"],
    love: ["Rishta shaadi tak jayega?", "Pyaar mein aage kya hai?"],
    children: ["Santan ka accha mahina kaunsa?", "Santan ke liye kya karun?"],
    career: ["Sarkari ya private job?", "Promotion kab milegi?"],
    money: ["Paisa kab tak sudhrega?", "Bachat kaise badhegi?"],
    debt: ["Karz kab se kam hoga?", "Karz ke liye kya karun?"],
    home: ["Ghar khareedun ya banaun?", "Naya ghar kaunse mahine lun?"],
    studies: ["Exam mein safalta kab?", "Kaunsi padhai sahi rahegi?"],
    general: ["Meri shaadi kab hogi?", "Career kaisa rahega?"],
  },
  hindi: {
    marriage: ["जीवनसाथी कैसा होगा?", "लव होगी या अरेंज?", "शादी में देरी क्यों?"],
    love: ["रिश्ता शादी तक जाएगा?", "प्यार में आगे क्या है?"],
    children: ["संतान का अच्छा महीना कौन सा?", "संतान के लिए क्या करूँ?"],
    career: ["सरकारी या प्राइवेट नौकरी?", "प्रमोशन कब मिलेगा?"],
    money: ["पैसों की हालत कब सुधरेगी?", "बचत कैसे बढ़ेगी?"],
    debt: ["कर्ज़ कब से कम होगा?", "कर्ज़ के लिए क्या करूँ?"],
    home: ["घर खरीदूँ या बनाऊँ?", "नया घर किस महीने लूँ?"],
    studies: ["परीक्षा में सफलता कब?", "कौन सी पढ़ाई सही रहेगी?"],
    general: ["मेरी शादी कब होगी?", "करियर कैसा रहेगा?"],
  },
  english: {
    marriage: ["What will my partner be like?", "Love or arranged marriage?", "Why is my marriage delayed?"],
    love: ["Will this lead to marriage?", "What's next in my love life?"],
    children: ["Best month for a child?", "What can I do for children?"],
    career: ["Government or private job?", "When is my promotion due?"],
    money: ["When will my finances improve?", "How can I save more money?"],
    debt: ["When will my debt reduce?", "How do I clear my loan?"],
    home: ["Buy or build a house?", "Best month to buy a home?"],
    studies: ["When will I clear my exam?", "Which studies suit me?"],
    general: ["When will I get married?", "How will my career go?"],
  },
  kannada: {
    marriage: ["ಸಂಗಾತಿ ಹೇಗಿರುತ್ತಾರೆ?", "ಲವ್ ಅಥವಾ ಅರೇಂಜ್ ಮದುವೆ?", "ಮದುವೆ ತಡ ಯಾಕೆ?"],
    love: ["ಈ ಪ್ರೀತಿ ಮದುವೆಗೆ ಹೋಗುತ್ತಾ?", "ಪ್ರೀತಿಯಲ್ಲಿ ಮುಂದೇನು?"],
    children: ["ಮಗುವಿಗೆ ಒಳ್ಳೆಯ ತಿಂಗಳು ಯಾವುದು?", "ಸಂತಾನಕ್ಕಾಗಿ ಏನು ಮಾಡಲಿ?"],
    career: ["ಸರ್ಕಾರಿ ಅಥವಾ ಖಾಸಗಿ ಕೆಲಸ?", "ಬಡ್ತಿ ಯಾವಾಗ ಸಿಗುತ್ತದೆ?"],
    money: ["ಹಣಕಾಸು ಯಾವಾಗ ಸುಧಾರಿಸುತ್ತದೆ?", "ಉಳಿತಾಯ ಹೇಗೆ ಹೆಚ್ಚಿಸಲಿ?"],
    debt: ["ಸಾಲ ಯಾವಾಗ ಕಡಿಮೆಯಾಗುತ್ತದೆ?", "ಸಾಲಕ್ಕಾಗಿ ಏನು ಮಾಡಲಿ?"],
    home: ["ಸ್ವಂತ ಮನೆ ಯಾವಾಗ?", "ಮನೆ ಕಟ್ಟಲೋ ಖರೀದಿಸಲೋ?"],
    studies: ["ಪರೀಕ್ಷೆಯಲ್ಲಿ ಯಶಸ್ಸು ಯಾವಾಗ?", "ಯಾವ ಶಿಕ್ಷಣ ಸೂಕ್ತ?"],
    general: ["ನನ್ನ ಮದುವೆ ಯಾವಾಗ?", "ನನ್ನ ವೃತ್ತಿ ಹೇಗಿರಲಿದೆ?"],
  },
  tamil: {
    marriage: ["வாழ்க்கைத் துணை எப்படி இருப்பார்?", "காதல் திருமணமா, பெற்றோர் பார்த்ததா?", "திருமணம் ஏன் தாமதம்?"],
    love: ["இந்த காதல் திருமணத்தில் முடியுமா?", "காதலில் அடுத்து என்ன?"],
    children: ["குழந்தைக்கு நல்ல மாதம் எது?", "குழந்தைக்காக என்ன செய்யலாம்?"],
    career: ["அரசு வேலையா, தனியார் வேலையா?", "பதவி உயர்வு எப்போது?"],
    money: ["பண நிலை எப்போது மேம்படும்?", "சேமிப்பை எப்படி உயர்த்துவது?"],
    debt: ["கடன் எப்போது குறையும்?", "கடனுக்கு என்ன செய்யலாம்?"],
    home: ["சொந்த வீடு எப்போது?", "வீடு கட்டவா, வாங்கவா?"],
    studies: ["தேர்வில் வெற்றி எப்போது?", "எந்த படிப்பு பொருத்தம்?"],
    general: ["என் திருமணம் எப்போது?", "என் தொழில் எப்படி இருக்கும்?"],
  },
  telugu: {
    marriage: ["జీవిత భాగస్వామి ఎలా ఉంటారు?", "ప్రేమ పెళ్లా, పెద్దలు కుదిర్చినదా?", "పెళ్లి ఎందుకు ఆలస్యం?"],
    love: ["ఈ ప్రేమ పెళ్లి వరకు వెళ్తుందా?", "ప్రేమలో తర్వాత ఏమిటి?"],
    children: ["సంతానానికి మంచి నెల ఏది?", "సంతానం కోసం ఏమి చేయాలి?"],
    career: ["ప్రభుత్వ ఉద్యోగమా, ప్రైవేటా?", "ప్రమోషన్ ఎప్పుడు?"],
    money: ["ఆర్థిక స్థితి ఎప్పుడు మెరుగవుతుంది?", "పొదుపు ఎలా పెంచాలి?"],
    debt: ["అప్పులు ఎప్పుడు తగ్గుతాయి?", "అప్పు కోసం ఏమి చేయాలి?"],
    home: ["సొంత ఇల్లు ఎప్పుడు?", "ఇల్లు కట్టాలా, కొనాలా?"],
    studies: ["పరీక్షలో విజయం ఎప్పుడు?", "ఏ చదువు సరిపోతుంది?"],
    general: ["నా పెళ్లి ఎప్పుడు?", "నా ఉద్యోగం ఎలా ఉంటుంది?"],
  },
  malayalam: {
    marriage: ["ജീവിതപങ്കാളി എങ്ങനെയായിരിക്കും?", "പ്രണയ വിവാഹമോ അറേഞ്ച്ഡോ?", "വിവാഹം എന്തുകൊണ്ട് വൈകുന്നു?"],
    love: ["ഈ പ്രണയം വിവാഹത്തിലെത്തുമോ?", "പ്രണയത്തിൽ അടുത്തത് എന്ത്?"],
    children: ["കുഞ്ഞിന് നല്ല മാസം ഏത്?", "സന്താനത്തിനായി എന്ത് ചെയ്യണം?"],
    career: ["സർക്കാർ ജോലിയോ സ്വകാര്യമോ?", "പ്രമോഷൻ എപ്പോൾ?"],
    money: ["സാമ്പത്തിക നില എപ്പോൾ മെച്ചപ്പെടും?", "സമ്പാദ്യം എങ്ങനെ കൂട്ടാം?"],
    debt: ["കടം എപ്പോൾ കുറയും?", "കടത്തിന് എന്ത് ചെയ്യണം?"],
    home: ["സ്വന്തം വീട് എപ്പോൾ?", "വീട് പണിയണോ വാങ്ങണോ?"],
    studies: ["പരീക്ഷയിൽ വിജയം എപ്പോൾ?", "ഏത് പഠനം യോജിക്കും?"],
    general: ["എന്റെ വിവാഹം എപ്പോൾ?", "എന്റെ ജോലി എങ്ങനെയായിരിക്കും?"],
  },
  marathi: {
    marriage: ["जोडीदार कसा असेल?", "लव्ह की अरेंज लग्न?", "लग्न उशिरा का?"],
    love: ["हे प्रेम लग्नापर्यंत जाईल का?", "प्रेमात पुढे काय?"],
    children: ["बाळासाठी चांगला महिना कोणता?", "संततीसाठी काय करू?"],
    career: ["सरकारी की खासगी नोकरी?", "बढती कधी मिळेल?"],
    money: ["पैशांची स्थिती कधी सुधारेल?", "बचत कशी वाढेल?"],
    debt: ["कर्ज कधी कमी होईल?", "कर्जासाठी काय करू?"],
    home: ["स्वतःचे घर कधी?", "घर बांधू की घेऊ?"],
    studies: ["परीक्षेत यश कधी?", "कोणतं शिक्षण योग्य?"],
    general: ["माझं लग्न कधी होईल?", "माझं करिअर कसं असेल?"],
  },
};

/** [topic]'s follow-ups in [language]; Hinglish for a language not here, as the yes chip does. */
export function fallbackOptions(topic: ReplyTopic, language: string): string[] {
  const table = FALLBACK[language.trim().toLowerCase()] ?? FALLBACK.hinglish;
  return table[topic] ?? [];
}

export const FALLBACK_LANGUAGES = Object.keys(FALLBACK);
