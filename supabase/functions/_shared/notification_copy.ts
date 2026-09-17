/**
 * What each push says, in each of the app's seven languages.
 *
 * Hand-written rather than generated: a notification is a sentence someone reads on a lock screen,
 * and a model writing "your stars have aligned" in Kannada at 8am with no review is not a risk
 * worth taking for text this short. **Telugu, Tamil, Kannada, Malayalam and Hindi need review by a
 * native speaker before their campaigns are switched on.**
 *
 * Script follows `chat_language.ts`: Hinglish and English in Roman letters, the others in their own
 * script. "Astro" and "Astrolok" stay in Latin everywhere, as the app writes them.
 *
 * `{name}` is the first name. Accounts with no name — the onboarding campaign, mostly — get the
 * sentence without it, see [renderCopy]. Titles stay within about 45 visible characters, where
 * Android starts truncating them.
 */

import { CampaignKey } from "./notification_campaigns.ts";

export interface PushCopy {
  title: string;
  body: string;
}

export const COPY_LANGUAGES = ["english", "hinglish", "hindi", "telugu", "tamil", "kannada", "malayalam"] as const;
export type CopyLanguage = typeof COPY_LANGUAGES[number];

export const COPY: Record<CampaignKey, Record<CopyLanguage, PushCopy>> = {
  mid_cancel: {
    english: { title: "Sorry to see you go, {name}", body: "Tell us in one tap what didn't work for you. It helps us make Astrolok better." },
    hinglish: { title: "Aapko jaate dekh dukh hua, {name}", body: "Ek tap mein bataiye kya kami rahi. Isse hum Astrolok ko behtar bana payenge." },
    hindi: { title: "आपको जाते देख दुख हुआ, {name}", body: "एक टैप में बताइए क्या कमी रही। इससे हम Astrolok को बेहतर बना पाएंगे।" },
    telugu: { title: "మీరు వెళ్లిపోవడం బాధగా ఉంది, {name}", body: "ఏది నచ్చలేదో ఒక్క ట్యాప్‌లో చెప్పండి. Astrolok ను మెరుగుపరచడానికి ఇది సహాయపడుతుంది." },
    tamil: { title: "நீங்கள் செல்வது வருத்தம், {name}", body: "எது பிடிக்கவில்லை என்று ஒரே தட்டலில் சொல்லுங்கள். Astrolok-ஐ மேம்படுத்த இது உதவும்." },
    kannada: { title: "ನೀವು ಹೋಗುತ್ತಿರುವುದು ಬೇಸರ, {name}", body: "ಯಾವುದು ಇಷ್ಟವಾಗಲಿಲ್ಲ ಎಂದು ಒಂದೇ ಟ್ಯಾಪ್‌ನಲ್ಲಿ ತಿಳಿಸಿ. Astrolok ಉತ್ತಮಗೊಳಿಸಲು ಇದು ಸಹಾಯ ಮಾಡುತ್ತದೆ." },
    malayalam: { title: "നിങ്ങൾ പോകുന്നതിൽ വിഷമമുണ്ട്, {name}", body: "എന്താണ് ഇഷ്ടപ്പെടാത്തതെന്ന് ഒറ്റ ടാപ്പിൽ പറയൂ. Astrolok മെച്ചപ്പെടുത്താൻ ഇത് സഹായിക്കും." },
  },
  billing_issue: {
    english: { title: "Your plan needs attention", body: "Your last autopay didn't go through. Fix it now to keep your readings and chat." },
    hinglish: { title: "Aapke plan par dhyaan dein", body: "Aapka pichhla autopay nahi hua. Readings aur chat jaari rakhne ke liye abhi theek karein." },
    hindi: { title: "आपके प्लान पर ध्यान दें", body: "आपका पिछला ऑटोपे नहीं हुआ। रीडिंग और चैट जारी रखने के लिए अभी ठीक करें।" },
    telugu: { title: "మీ ప్లాన్‌ను ఒకసారి చూడండి", body: "మీ చివరి ఆటోపే విఫలమైంది. రీడింగ్‌లు, చాట్ కొనసాగించడానికి ఇప్పుడే సరిచేయండి." },
    tamil: { title: "உங்கள் திட்டத்தைக் கவனியுங்கள்", body: "உங்கள் கடைசி ஆட்டோபே தோல்வியடைந்தது. ரீடிங்கும் சாட்டும் தொடர இப்போதே சரிசெய்யுங்கள்." },
    kannada: { title: "ನಿಮ್ಮ ಪ್ಲಾನ್ ಗಮನಿಸಿ", body: "ನಿಮ್ಮ ಕೊನೆಯ ಆಟೋಪೇ ವಿಫಲವಾಗಿದೆ. ರೀಡಿಂಗ್ ಮತ್ತು ಚಾಟ್ ಮುಂದುವರಿಸಲು ಈಗಲೇ ಸರಿಪಡಿಸಿ." },
    malayalam: { title: "നിങ്ങളുടെ പ്ലാൻ ശ്രദ്ധിക്കൂ", body: "നിങ്ങളുടെ അവസാന ഓട്ടോപേ പരാജയപ്പെട്ടു. റീഡിംഗും ചാറ്റും തുടരാൻ ഇപ്പോൾ തന്നെ ശരിയാക്കൂ." },
  },
  kundali_ready: {
    english: { title: "✨ Your Kundali is ready", body: "{name}, your stars have been mapped. Tap to reveal your birth chart and life insights." },
    hinglish: { title: "✨ Aapki Kundali taiyaar hai", body: "{name}, aapke sitaron ka naksha ban gaya hai. Apni janm kundali dekhne ke liye tap karein." },
    hindi: { title: "✨ आपकी कुंडली तैयार है", body: "{name}, आपके सितारों का नक्शा बन गया है। अपनी जन्म कुंडली देखने के लिए टैप करें।" },
    telugu: { title: "✨ మీ జాతకం సిద్ధంగా ఉంది", body: "{name}, మీ గ్రహస్థితి సిద్ధమైంది. మీ జన్మ కుండలిని చూడటానికి ట్యాప్ చేయండి." },
    tamil: { title: "✨ உங்கள் ஜாதகம் தயார்", body: "{name}, உங்கள் கிரக நிலைகள் கணிக்கப்பட்டன. உங்கள் ஜனன ஜாதகத்தைக் காண தட்டுங்கள்." },
    kannada: { title: "✨ ನಿಮ್ಮ ಜಾತಕ ಸಿದ್ಧವಾಗಿದೆ", body: "{name}, ನಿಮ್ಮ ಗ್ರಹಸ್ಥಿತಿ ಸಿದ್ಧವಾಗಿದೆ. ನಿಮ್ಮ ಜನ್ಮ ಕುಂಡಲಿ ನೋಡಲು ಟ್ಯಾಪ್ ಮಾಡಿ." },
    malayalam: { title: "✨ നിങ്ങളുടെ ജാതകം തയ്യാർ", body: "{name}, നിങ്ങളുടെ ഗ്രഹനില തയ്യാറായി. നിങ്ങളുടെ ജനന ജാതകം കാണാൻ ടാപ്പ് ചെയ്യൂ." },
  },
  kundali_ready_lapsed: {
    english: { title: "✨ Your Kundali is ready", body: "Your birth chart is waiting for you. Renew your plan to reveal it." },
    hinglish: { title: "✨ Aapki Kundali taiyaar hai", body: "Aapki janm kundali intezaar kar rahi hai. Dekhne ke liye apna plan renew karein." },
    hindi: { title: "✨ आपकी कुंडली तैयार है", body: "आपकी जन्म कुंडली इंतज़ार कर रही है। देखने के लिए अपना प्लान रिन्यू करें।" },
    telugu: { title: "✨ మీ జాతకం సిద్ధంగా ఉంది", body: "మీ జన్మ కుండలి మీ కోసం ఎదురుచూస్తోంది. చూడటానికి మీ ప్లాన్‌ను రెన్యూ చేయండి." },
    tamil: { title: "✨ உங்கள் ஜாதகம் தயார்", body: "உங்கள் ஜனன ஜாதகம் காத்திருக்கிறது. காண உங்கள் திட்டத்தைப் புதுப்பியுங்கள்." },
    kannada: { title: "✨ ನಿಮ್ಮ ಜಾತಕ ಸಿದ್ಧವಾಗಿದೆ", body: "ನಿಮ್ಮ ಜನ್ಮ ಕುಂಡಲಿ ಕಾಯುತ್ತಿದೆ. ನೋಡಲು ನಿಮ್ಮ ಪ್ಲಾನ್ ನವೀಕರಿಸಿ." },
    malayalam: { title: "✨ നിങ്ങളുടെ ജാതകം തയ്യാർ", body: "നിങ്ങളുടെ ജനന ജാതകം കാത്തിരിക്കുന്നു. കാണാൻ നിങ്ങളുടെ പ്ലാൻ പുതുക്കൂ." },
  },
  kundali_halfway: {
    english: { title: "Your Kundali is halfway there 🪔", body: "The planets are settling into place. Your birth chart will be revealed soon. Take a peek." },
    hinglish: { title: "Aapki Kundali aadhi taiyaar hai 🪔", body: "Grah apni jagah le rahe hain. Aapki kundali jald hi saamne aayegi. Ek nazar daaliye." },
    hindi: { title: "आपकी कुंडली आधी तैयार है 🪔", body: "ग्रह अपनी जगह ले रहे हैं। आपकी कुंडली जल्द ही सामने आएगी। एक नज़र डालिए।" },
    telugu: { title: "మీ జాతకం సగం సిద్ధమైంది 🪔", body: "గ్రహాలు తమ స్థానాల్లోకి వస్తున్నాయి. మీ కుండలి త్వరలో వెల్లడవుతుంది. ఒకసారి చూడండి." },
    tamil: { title: "உங்கள் ஜாதகம் பாதி தயார் 🪔", body: "கிரகங்கள் தங்கள் இடத்தில் அமைகின்றன. உங்கள் ஜாதகம் விரைவில் வெளிப்படும். ஒரு பார்வை பாருங்கள்." },
    kannada: { title: "ನಿಮ್ಮ ಜಾತಕ ಅರ್ಧ ಸಿದ್ಧ 🪔", body: "ಗ್ರಹಗಳು ತಮ್ಮ ಸ್ಥಾನಕ್ಕೆ ಬರುತ್ತಿವೆ. ನಿಮ್ಮ ಕುಂಡಲಿ ಶೀಘ್ರದಲ್ಲೇ ತೆರೆದುಕೊಳ್ಳುತ್ತದೆ. ಒಮ್ಮೆ ನೋಡಿ." },
    malayalam: { title: "ജാതകം പകുതി തയ്യാറായി 🪔", body: "ഗ്രഹങ്ങൾ അവയുടെ സ്ഥാനങ്ങളിലേക്ക് എത്തുന്നു. നിങ്ങളുടെ ജാതകം ഉടൻ വെളിപ്പെടും. ഒന്ന് നോക്കൂ." },
  },
  kundali_not_opened: {
    english: { title: "Your Kundali is still waiting 🔮", body: "{name}, your birth chart and life insights are ready. Don't miss what your stars say." },
    hinglish: { title: "Aapki Kundali intezaar mein hai 🔮", body: "{name}, aapki kundali aur jeevan ki baatein taiyaar hain. Dekhna mat bhooliye." },
    hindi: { title: "आपकी कुंडली इंतज़ार में है 🔮", body: "{name}, आपकी कुंडली और जीवन की बातें तैयार हैं। देखना न भूलें।" },
    telugu: { title: "మీ జాతకం ఎదురుచూస్తోంది 🔮", body: "{name}, మీ కుండలి మరియు జీవిత సూచనలు సిద్ధంగా ఉన్నాయి. చూడటం మర్చిపోకండి." },
    tamil: { title: "உங்கள் ஜாதகம் காத்திருக்கிறது 🔮", body: "{name}, உங்கள் ஜாதகமும் வாழ்க்கைக் குறிப்புகளும் தயார். பார்க்க மறக்காதீர்கள்." },
    kannada: { title: "ನಿಮ್ಮ ಜಾತಕ ಕಾಯುತ್ತಿದೆ 🔮", body: "{name}, ನಿಮ್ಮ ಕುಂಡಲಿ ಮತ್ತು ಜೀವನದ ಸೂಚನೆಗಳು ಸಿದ್ಧವಾಗಿವೆ. ನೋಡಲು ಮರೆಯಬೇಡಿ." },
    malayalam: { title: "ജാതകം കാത്തിരിക്കുന്നു 🔮", body: "{name}, നിങ്ങളുടെ ജാതകവും ജീവിത സൂചനകളും തയ്യാറാണ്. കാണാൻ മറക്കരുത്." },
  },
  palm_no_face: {
    english: { title: "Your face tells a story too", body: "You've read your palm. Now see what your face reveals about you." },
    hinglish: { title: "Aapka chehra bhi kuch kehta hai", body: "Haath ki lakeeron ke baad ab dekhiye aapka chehra aapke baare mein kya batata hai." },
    hindi: { title: "आपका चेहरा भी कुछ कहता है", body: "हाथ की रेखाओं के बाद अब देखिए आपका चेहरा आपके बारे में क्या बताता है।" },
    telugu: { title: "మీ ముఖం కూడా ఏదో చెబుతుంది", body: "మీ అరచేతిని చదివారు. ఇప్పుడు మీ ముఖం మీ గురించి ఏమి చెబుతుందో చూడండి." },
    tamil: { title: "உங்கள் முகமும் ஒரு கதை சொல்கிறது", body: "உங்கள் கைரேகையைப் பார்த்தீர்கள். இப்போது உங்கள் முகம் உங்களைப் பற்றி என்ன சொல்கிறது என்று பாருங்கள்." },
    kannada: { title: "ನಿಮ್ಮ ಮುಖವೂ ಏನೋ ಹೇಳುತ್ತದೆ", body: "ನಿಮ್ಮ ಅಂಗೈ ಓದಿದ್ದೀರಿ. ಈಗ ನಿಮ್ಮ ಮುಖ ನಿಮ್ಮ ಬಗ್ಗೆ ಏನು ಹೇಳುತ್ತದೆ ನೋಡಿ." },
    malayalam: { title: "നിങ്ങളുടെ മുഖത്തിനും ഒരു കഥയുണ്ട്", body: "നിങ്ങളുടെ കൈരേഖ വായിച്ചു. ഇനി നിങ്ങളുടെ മുഖം നിങ്ങളെക്കുറിച്ച് എന്ത് പറയുന്നു എന്ന് കാണൂ." },
  },
  reading_no_chat: {
    english: { title: "A question about your reading?", body: "Ask Astro anything about love, career or the months ahead." },
    hinglish: { title: "Apni reading par koi sawaal?", body: "Pyaar, career ya aane wale samay ke baare mein Astro se kuch bhi poochiye." },
    hindi: { title: "अपनी रीडिंग पर कोई सवाल?", body: "प्यार, करियर या आने वाले समय के बारे में Astro से कुछ भी पूछिए।" },
    telugu: { title: "మీ రీడింగ్ గురించి ప్రశ్న ఉందా?", body: "ప్రేమ, కెరీర్ లేదా రాబోయే రోజుల గురించి Astro ను ఏదైనా అడగండి." },
    tamil: { title: "உங்கள் ரீடிங் பற்றி கேள்வியா?", body: "காதல், வேலை அல்லது வரும் நாட்கள் பற்றி Astro-விடம் எதையும் கேளுங்கள்." },
    kannada: { title: "ನಿಮ್ಮ ರೀಡಿಂಗ್ ಬಗ್ಗೆ ಪ್ರಶ್ನೆ ಇದೆಯೇ?", body: "ಪ್ರೀತಿ, ವೃತ್ತಿ ಅಥವಾ ಮುಂದಿನ ದಿನಗಳ ಬಗ್ಗೆ Astro ಅನ್ನು ಏನು ಬೇಕಾದರೂ ಕೇಳಿ." },
    malayalam: { title: "റീഡിംഗിനെക്കുറിച്ച് ചോദ്യമുണ്ടോ?", body: "പ്രണയം, ജോലി അല്ലെങ്കിൽ വരും ദിവസങ്ങളെക്കുറിച്ച് Astro-യോട് എന്തും ചോദിക്കൂ." },
  },
  trial_no_reading: {
    english: { title: "Your first reading is waiting 🖐️", body: "Your plan includes a palm and a face reading. See what your hand says in 30 seconds." },
    hinglish: { title: "Aapki pehli reading intezaar mein 🖐️", body: "Aapke plan mein palm aur face reading shaamil hai. 30 second mein dekhiye aapka haath kya kehta hai." },
    hindi: { title: "आपकी पहली रीडिंग इंतज़ार में 🖐️", body: "आपके प्लान में हस्त और चेहरा रीडिंग शामिल है। 30 सेकंड में देखिए आपका हाथ क्या कहता है।" },
    telugu: { title: "మీ మొదటి రీడింగ్ ఎదురుచూస్తోంది 🖐️", body: "మీ ప్లాన్‌లో అరచేయి, ముఖ రీడింగ్ ఉన్నాయి. మీ చేయి ఏమి చెబుతుందో 30 సెకన్లలో చూడండి." },
    tamil: { title: "உங்கள் முதல் ரீடிங் காத்திருக்கிறது 🖐️", body: "உங்கள் திட்டத்தில் கைரேகை, முக ரீடிங் உள்ளன. உங்கள் கை என்ன சொல்கிறது என்று 30 வினாடிகளில் பாருங்கள்." },
    kannada: { title: "ನಿಮ್ಮ ಮೊದಲ ರೀಡಿಂಗ್ ಕಾಯುತ್ತಿದೆ 🖐️", body: "ನಿಮ್ಮ ಪ್ಲಾನ್‌ನಲ್ಲಿ ಅಂಗೈ ಮತ್ತು ಮುಖ ರೀಡಿಂಗ್ ಇದೆ. ನಿಮ್ಮ ಕೈ ಏನು ಹೇಳುತ್ತದೆ ಎಂದು 30 ಸೆಕೆಂಡುಗಳಲ್ಲಿ ನೋಡಿ." },
    malayalam: { title: "ആദ്യ റീഡിംഗ് കാത്തിരിക്കുന്നു 🖐️", body: "നിങ്ങളുടെ പ്ലാനിൽ കൈരേഖ, മുഖ റീഡിംഗ് ഉണ്ട്. നിങ്ങളുടെ കൈ എന്ത് പറയുന്നു എന്ന് 30 സെക്കൻഡിൽ കാണൂ." },
  },
  paywall_abandoned: {
    english: { title: "Your stars are waiting, {name}", body: "Start your trial today and unlock palm reading, face reading and chat with Astro." },
    hinglish: { title: "Aapke sitare intezaar mein hain, {name}", body: "Aaj hi trial shuru karein aur palm reading, face reading aur Astro chat unlock karein." },
    hindi: { title: "आपके सितारे इंतज़ार में हैं, {name}", body: "आज ही ट्रायल शुरू करें और हस्त रीडिंग, चेहरा रीडिंग और Astro चैट अनलॉक करें।" },
    telugu: { title: "మీ నక్షత్రాలు ఎదురుచూస్తున్నాయి, {name}", body: "ఈరోజే ట్రయల్ ప్రారంభించి అరచేయి, ముఖ రీడింగ్ మరియు Astro చాట్ పొందండి." },
    tamil: { title: "நட்சத்திரங்கள் காத்திருக்கின்றன, {name}", body: "இன்றே ட்ரையலைத் தொடங்கி கைரேகை, முக ரீடிங் மற்றும் Astro சாட்டைப் பெறுங்கள்." },
    kannada: { title: "ನಿಮ್ಮ ನಕ್ಷತ್ರಗಳು ಕಾಯುತ್ತಿವೆ, {name}", body: "ಇಂದೇ ಟ್ರಯಲ್ ಆರಂಭಿಸಿ ಅಂಗೈ, ಮುಖ ರೀಡಿಂಗ್ ಮತ್ತು Astro ಚಾಟ್ ಪಡೆಯಿರಿ." },
    malayalam: { title: "നക്ഷത്രങ്ങൾ കാത്തിരിക്കുന്നു, {name}", body: "ഇന്നുതന്നെ ട്രയൽ ആരംഭിച്ച് കൈരേഖ, മുഖ റീഡിംഗ്, Astro ചാറ്റ് എന്നിവ നേടൂ." },
  },
  onboarding_incomplete: {
    english: { title: "Just one step left 🙏", body: "Add your birth date to unlock your personal readings." },
    hinglish: { title: "Bas ek kadam baaki 🙏", body: "Apni janm tithi jodiye aur apni personal readings unlock kijiye." },
    hindi: { title: "बस एक कदम बाकी 🙏", body: "अपनी जन्म तिथि जोड़िए और अपनी व्यक्तिगत रीडिंग अनलॉक कीजिए।" },
    telugu: { title: "ఇంకా ఒక్క అడుగు మాత్రమే 🙏", body: "మీ పుట్టిన తేదీని జోడించి మీ వ్యక్తిగత రీడింగ్‌లను పొందండి." },
    tamil: { title: "இன்னும் ஒரு படி மட்டுமே 🙏", body: "உங்கள் பிறந்த தேதியைச் சேர்த்து உங்கள் தனிப்பட்ட ரீடிங்குகளைப் பெறுங்கள்." },
    kannada: { title: "ಇನ್ನೊಂದೇ ಹೆಜ್ಜೆ ಬಾಕಿ 🙏", body: "ನಿಮ್ಮ ಜನ್ಮ ದಿನಾಂಕ ಸೇರಿಸಿ ಮತ್ತು ನಿಮ್ಮ ವೈಯಕ್ತಿಕ ರೀಡಿಂಗ್‌ಗಳನ್ನು ಪಡೆಯಿರಿ." },
    malayalam: { title: "ഇനി ഒരു ചുവട് മാത്രം 🙏", body: "നിങ്ങളുടെ ജനനത്തീയതി ചേർത്ത് വ്യക്തിഗത റീഡിംഗുകൾ നേടൂ." },
  },
  post_charge_no_return: {
    english: { title: "Your readings are waiting", body: "Your plan is active. Explore your Kundali, palm reading and chat with Astro today." },
    hinglish: { title: "Aapki readings intezaar mein hain", body: "Aapka plan active hai. Aaj hi apni Kundali, palm reading aur Astro chat dekhiye." },
    hindi: { title: "आपकी रीडिंग इंतज़ार में हैं", body: "आपका प्लान सक्रिय है। आज ही अपनी कुंडली, हस्त रीडिंग और Astro चैट देखिए।" },
    telugu: { title: "మీ రీడింగ్‌లు ఎదురుచూస్తున్నాయి", body: "మీ ప్లాన్ యాక్టివ్‌గా ఉంది. ఈరోజే మీ జాతకం, అరచేయి రీడింగ్, Astro చాట్ చూడండి." },
    tamil: { title: "உங்கள் ரீடிங்குகள் காத்திருக்கின்றன", body: "உங்கள் திட்டம் செயலில் உள்ளது. இன்றே உங்கள் ஜாதகம், கைரேகை ரீடிங், Astro சாட்டைப் பாருங்கள்." },
    kannada: { title: "ನಿಮ್ಮ ರೀಡಿಂಗ್‌ಗಳು ಕಾಯುತ್ತಿವೆ", body: "ನಿಮ್ಮ ಪ್ಲಾನ್ ಸಕ್ರಿಯವಾಗಿದೆ. ಇಂದೇ ನಿಮ್ಮ ಜಾತಕ, ಅಂಗೈ ರೀಡಿಂಗ್ ಮತ್ತು Astro ಚಾಟ್ ನೋಡಿ." },
    malayalam: { title: "റീഡിംഗുകൾ കാത്തിരിക്കുന്നു", body: "നിങ്ങളുടെ പ്ലാൻ സജീവമാണ്. ഇന്നുതന്നെ നിങ്ങളുടെ ജാതകം, കൈരേഖ റീഡിംഗ്, Astro ചാറ്റ് കാണൂ." },
  },
  winback_paid: {
    english: { title: "We miss you, {name}", body: "Your stars have moved since we last met. Come back and see what's new for you." },
    hinglish: { title: "Hum aapko yaad kar rahe hain, {name}", body: "Pichhli mulaqat ke baad sitare badal gaye hain. Wapas aaiye aur dekhiye kya naya hai." },
    hindi: { title: "हम आपको याद कर रहे हैं, {name}", body: "पिछली मुलाकात के बाद सितारे बदल गए हैं। वापस आइए और देखिए क्या नया है।" },
    telugu: { title: "మిమ్మల్ని మిస్ అవుతున్నాం, {name}", body: "మనం చివరిసారి కలిసినప్పటి నుండి నక్షత్రాలు మారాయి. తిరిగి వచ్చి కొత్తగా ఏముందో చూడండి." },
    tamil: { title: "உங்களை மிஸ் செய்கிறோம், {name}", body: "நாம் கடைசியாகச் சந்தித்த பிறகு நட்சத்திரங்கள் மாறியுள்ளன. திரும்பி வந்து புதிதாக என்ன என்று பாருங்கள்." },
    kannada: { title: "ನಿಮ್ಮನ್ನು ಮಿಸ್ ಮಾಡುತ್ತಿದ್ದೇವೆ, {name}", body: "ನಾವು ಕೊನೆಯ ಬಾರಿ ಭೇಟಿಯಾದ ನಂತರ ನಕ್ಷತ್ರಗಳು ಬದಲಾಗಿವೆ. ಮರಳಿ ಬಂದು ಹೊಸದೇನು ನೋಡಿ." },
    malayalam: { title: "നിങ്ങളെ മിസ് ചെയ്യുന്നു, {name}", body: "നമ്മൾ അവസാനം കണ്ടതിനുശേഷം നക്ഷത്രങ്ങൾ മാറി. തിരികെ വന്ന് പുതിയതെന്തെന്ന് കാണൂ." },
  },
  dormant: {
    english: { title: "What does this week hold?", body: "{name}, ask Astro what the stars say about your week." },
    hinglish: { title: "Is hafte kya likha hai?", body: "{name}, Astro se poochiye sitare aapke is hafte ke baare mein kya kehte hain." },
    hindi: { title: "इस हफ़्ते क्या लिखा है?", body: "{name}, Astro से पूछिए सितारे आपके इस हफ़्ते के बारे में क्या कहते हैं।" },
    telugu: { title: "ఈ వారం మీకు ఏముంది?", body: "{name}, ఈ వారం గురించి నక్షత్రాలు ఏమి చెబుతున్నాయో Astro ను అడగండి." },
    tamil: { title: "இந்த வாரம் உங்களுக்கு என்ன?", body: "{name}, இந்த வாரம் பற்றி நட்சத்திரங்கள் என்ன சொல்கின்றன என்று Astro-விடம் கேளுங்கள்." },
    kannada: { title: "ಈ ವಾರ ನಿಮಗೇನಿದೆ?", body: "{name}, ಈ ವಾರದ ಬಗ್ಗೆ ನಕ್ಷತ್ರಗಳು ಏನು ಹೇಳುತ್ತವೆ ಎಂದು Astro ಅನ್ನು ಕೇಳಿ." },
    malayalam: { title: "ഈ ആഴ്ച നിങ്ങൾക്കായി എന്ത്?", body: "{name}, ഈ ആഴ്ചയെക്കുറിച്ച് നക്ഷത്രങ്ങൾ എന്ത് പറയുന്നു എന്ന് Astro-യോട് ചോദിക്കൂ." },
  },
};

/** A first name safe to put on a lock screen: one word, trimmed, never longer than 20 characters. */
function nameFor(name: string | null | undefined): string | null {
  const first = (name ?? "").trim().split(/\s+/)[0] ?? "";
  if (!first) return null;
  return Array.from(first).slice(0, 20).join("");
}

function fill(template: string, name: string | null): string {
  if (name) return template.replaceAll("{name}", name);

  // Without a name, the sentence has to read as if it never had one: "{name}, your stars…" becomes
  // "Your stars…", and "We miss you, {name}" becomes "We miss you".
  const text = template
    .replace(/\s*,\s*\{name\}/g, "")
    .replace(/\{name\}\s*,\s*/g, "")
    .replaceAll("{name}", "")
    .replace(/\s+/g, " ")
    .trim();
  return /^[a-z]/.test(text) ? text[0].toUpperCase() + text.slice(1) : text;
}

/**
 * The title and body for [campaign] in [language] (any case; unknown languages get English), with
 * the language actually used, which is what `notifications.language` records.
 */
export function renderCopy(
  campaign: CampaignKey,
  language: string | null | undefined,
  { name }: { name?: string | null } = {},
): PushCopy & { language: CopyLanguage } {
  const wanted = (language ?? "").trim().toLowerCase() as CopyLanguage;
  const resolved: CopyLanguage = (COPY_LANGUAGES as readonly string[]).includes(wanted) ? wanted : "english";
  const template = COPY[campaign][resolved];
  const first = nameFor(name);
  return { title: fill(template.title, first), body: fill(template.body, first), language: resolved };
}
