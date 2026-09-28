import 'package:flutter/foundation.dart';

/// What Astro says before anyone has said anything, in the person's own language.
///
/// The WhatsApp-style chat opens the way a real one does — a message already waiting from the
/// other side — rather than on a menu. The topics are the v5 plan's demand order: marriage and
/// love are half of everything typed (28.5% and 22.5%), then children, a home, work, money. Each
/// is written the way people actually type it, because tapping one sends it as their own words.
///
/// Hindi and Hinglish were checked against real messages; Kannada, Tamil, Telugu and Malayalam
/// still want a native speaker's pass before they are relied on.
@immutable
class ChatGreeting {
  const ChatGreeting({
    required this.hello,
    required this.note,
    required this.topics,
    required this.pickTime,
    required this.dontKnow,
    required this.dobHint,
    required this.timeHint,
    required this.placeholder,
  });

  /// Astro's first message.
  final String hello;

  /// The yellow line at the very top: what Astro reads from, and that it is private.
  final String note;

  /// The questions offered under the greeting, in demand order.
  final List<String> topics;

  /// The button that opens the birth-time picker when Astro asks for the hour.
  final String pickTime;

  /// Sent when they do not know their birth time. The server reads it in every language.
  final String dontKnow;

  /// Composer hints while Astro is waiting for a date or an hour of birth.
  final String dobHint;
  final String timeHint;

  final String placeholder;

  /// The greeting for a chat language as the dashboard spells it ("Hindi"). English otherwise.
  static ChatGreeting of(String language) =>
      _byLanguage[language.trim().toLowerCase()] ?? _byLanguage['english']!;

  static const _byLanguage = <String, ChatGreeting>{
    'hinglish': ChatGreeting(
      hello: 'Namaste 🙏 Main Astro hoon. Aapki kundali dekh kar aapke har sawal ka jawab '
          'dunga. Kya poochna chahenge?',
      note: '🔒 Aapki baatein private hain. Astro aapki kundali, hatheli aur chehre se jawab '
          'deta hai.',
      topics: [
        'Meri shaadi kab hogi?',
        'Mera pyaar mujhe milega?',
        'Bachcha kab hoga?',
        'Apna ghar kab banega?',
        'Naukri kab lagegi?',
        'Paisa aur karz kab sudhrega?',
      ],
      pickTime: '⏰ Samay chunein',
      dontKnow: 'Pata nahi',
      dobHint: 'Jaise 15 August 1998',
      timeHint: 'Jaise shaam 7:30',
      placeholder: 'Message',
    ),
    'hindi': ChatGreeting(
      hello: 'नमस्ते 🙏 मैं Astro हूँ। आपकी कुंडली देखकर आपके हर सवाल का जवाब दूँगा। क्या पूछना '
          'चाहेंगे?',
      note: '🔒 आपकी बातें निजी हैं। Astro आपकी कुंडली, हथेली और चेहरे से जवाब देता है।',
      topics: [
        'मेरी शादी कब होगी?',
        'क्या मेरा प्यार मुझे मिलेगा?',
        'बच्चा कब होगा?',
        'अपना घर कब बनेगा?',
        'नौकरी कब लगेगी?',
        'पैसा और कर्ज़ कब सुधरेगा?',
      ],
      pickTime: '⏰ समय चुनें',
      dontKnow: 'पता नहीं',
      dobHint: 'जैसे 15 अगस्त 1998',
      timeHint: 'जैसे शाम 7:30',
      placeholder: 'संदेश',
    ),
    'english': ChatGreeting(
      hello: "Namaste 🙏 I'm Astro. I'll answer every question from your kundali. What would you "
          'like to ask?',
      note: '🔒 Your chat is private. Astro answers from your kundali, palm and face.',
      topics: [
        'When will I get married?',
        'Will I find my love?',
        'When will I have a child?',
        'When will I own a home?',
        'When will I get a job?',
        'When will money and debt improve?',
      ],
      pickTime: '⏰ Choose time',
      dontKnow: 'I do not know',
      dobHint: 'e.g. 15 August 1998',
      timeHint: 'e.g. 7:30 in the evening',
      placeholder: 'Message',
    ),
    'kannada': ChatGreeting(
      hello: 'ನಮಸ್ಕಾರ 🙏 ನಾನು Astro. ನಿಮ್ಮ ಜಾತಕ ನೋಡಿ ನಿಮ್ಮ ಪ್ರತಿಯೊಂದು ಪ್ರಶ್ನೆಗೆ ಉತ್ತರ ಕೊಡುತ್ತೇನೆ. '
          'ಏನು ಕೇಳಬೇಕು?',
      note: '🔒 ನಿಮ್ಮ ಮಾತುಕತೆ ಖಾಸಗಿ. Astro ನಿಮ್ಮ ಜಾತಕ, ಅಂಗೈ ಮತ್ತು ಮುಖದಿಂದ ಉತ್ತರಿಸುತ್ತದೆ.',
      topics: [
        'ನನ್ನ ಮದುವೆ ಯಾವಾಗ?',
        'ನನ್ನ ಪ್ರೀತಿ ಸಿಗುತ್ತದೆಯೇ?',
        'ಮಗು ಯಾವಾಗ?',
        'ಸ್ವಂತ ಮನೆ ಯಾವಾಗ?',
        'ಕೆಲಸ ಯಾವಾಗ ಸಿಗುತ್ತದೆ?',
        'ಹಣ ಮತ್ತು ಸಾಲ ಯಾವಾಗ ಸುಧಾರಿಸುತ್ತದೆ?',
      ],
      pickTime: '⏰ ಸಮಯ ಆರಿಸಿ',
      dontKnow: 'ಗೊತ್ತಿಲ್ಲ',
      dobHint: 'ಉದಾ: 15 ಆಗಸ್ಟ್ 1998',
      timeHint: 'ಉದಾ: ಸಂಜೆ 7:30',
      placeholder: 'ಸಂದೇಶ',
    ),
    'tamil': ChatGreeting(
      hello: 'வணக்கம் 🙏 நான் Astro. உங்கள் ஜாதகத்தைப் பார்த்து உங்கள் ஒவ்வொரு கேள்விக்கும் பதில் '
          'சொல்வேன். என்ன கேட்க விரும்புகிறீர்கள்?',
      note: '🔒 உங்கள் உரையாடல் தனிப்பட்டது. Astro உங்கள் ஜாதகம், உள்ளங்கை, முகம் மூலம் பதில் '
          'சொல்கிறது.',
      topics: [
        'என் திருமணம் எப்போது?',
        'என் காதல் கைகூடுமா?',
        'குழந்தை எப்போது?',
        'சொந்த வீடு எப்போது?',
        'வேலை எப்போது கிடைக்கும்?',
        'பணம், கடன் எப்போது சரியாகும்?',
      ],
      pickTime: '⏰ நேரம் தேர்வு செய்க',
      dontKnow: 'தெரியாது',
      dobHint: 'உதா: 15 ஆகஸ்ட் 1998',
      timeHint: 'உதா: மாலை 7:30',
      placeholder: 'செய்தி',
    ),
    'telugu': ChatGreeting(
      hello: 'నమస్కారం 🙏 నేను Astro. మీ జాతకం చూసి మీ ప్రతి ప్రశ్నకు సమాధానం చెబుతాను. ఏమి '
          'అడగాలనుకుంటున్నారు?',
      note: '🔒 మీ సంభాషణ గోప్యం. Astro మీ జాతకం, అరచేయి, ముఖం ఆధారంగా సమాధానం ఇస్తుంది.',
      topics: [
        'నా పెళ్లి ఎప్పుడు?',
        'నా ప్రేమ ఫలిస్తుందా?',
        'పిల్లలు ఎప్పుడు?',
        'సొంత ఇల్లు ఎప్పుడు?',
        'ఉద్యోగం ఎప్పుడు వస్తుంది?',
        'డబ్బు, అప్పు ఎప్పుడు మెరుగవుతాయి?',
      ],
      pickTime: '⏰ సమయం ఎంచుకోండి',
      dontKnow: 'తెలియదు',
      dobHint: 'ఉదా: 15 ఆగస్టు 1998',
      timeHint: 'ఉదా: సాయంత్రం 7:30',
      placeholder: 'సందేశం',
    ),
    'malayalam': ChatGreeting(
      hello: 'നമസ്കാരം 🙏 ഞാൻ Astro. നിങ്ങളുടെ ജാതകം നോക്കി ഓരോ ചോദ്യത്തിനും ഉത്തരം പറയാം. '
          'എന്താണ് ചോദിക്കേണ്ടത്?',
      note: '🔒 നിങ്ങളുടെ സംഭാഷണം സ്വകാര്യമാണ്. Astro നിങ്ങളുടെ ജാതകം, കൈപ്പത്തി, മുഖം എന്നിവയിൽ '
          'നിന്ന് ഉത്തരം നൽകുന്നു.',
      topics: [
        'എന്റെ വിവാഹം എപ്പോൾ?',
        'എന്റെ പ്രണയം സഫലമാകുമോ?',
        'കുഞ്ഞ് എപ്പോൾ?',
        'സ്വന്തം വീട് എപ്പോൾ?',
        'ജോലി എപ്പോൾ കിട്ടും?',
        'പണവും കടവും എപ്പോൾ മെച്ചപ്പെടും?',
      ],
      pickTime: '⏰ സമയം തിരഞ്ഞെടുക്കൂ',
      dontKnow: 'അറിയില്ല',
      dobHint: 'ഉദാ: 15 ഓഗസ്റ്റ് 1998',
      timeHint: 'ഉദാ: വൈകുന്നേരം 7:30',
      placeholder: 'സന്ദേശം',
    ),
  };
}
