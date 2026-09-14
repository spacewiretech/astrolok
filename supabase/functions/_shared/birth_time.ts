/**
 * Reading a time of birth out of something a person said.
 *
 * Not `parseClock` in `jyotish.ts`, which accepts only the `HH:MM` a Postgres `time` column
 * renders: that one reads a stored value, this one reads a sentence the sage recorded. Apart from
 * `astro-chat` so it can be tested — a time promoted from here onto `users.birth_time` is never
 * overwritten by a later sentence, so a wrong reading here is a wrong chart for good.
 */

/** Words that put an hour after midday: "11:55 pm", "shaam 6:30", "दोपहर 2:30". */
const AFTERNOON =
  /(?<![a-z])(?:pm|p\.m\.|evening|afternoon|noon|shaam|sham|dopahar|dopehar)(?![a-z])|शाम|दोपहर/i;

/** Night, which in Hindi runs past midnight: "raat 11:55" is 23:55, "raat 2 baje" is 02:00. */
const NIGHT = /(?<![a-z])(?:night|midnight|raat)(?![a-z])|रात/i;

const MORNING = /(?<![a-z])(?:am|a\.m\.|morning|subah|subha|savere|sawere)(?![a-z])|सुबह|सवेरे/i;

/** Before this hour, "raat" means the small hours rather than the evening. */
const NIGHT_BECOMES_EVENING = 5;

export interface StatedClock {
  /** `HH:MM`, or null when nothing usable was said. */
  time: string | null;

  /** True when a time was said but not which half of the day. */
  ambiguous: boolean;
}

/**
 * A stated time as `HH:MM`, and whether it was too ambiguous to use.
 *
 * Deliberately narrow. The sage is asked to record what it heard, and what it heard might be
 * "around sunrise" — which is not a time, and guessing one would put a wrong nakshatra in front
 * of the user with all the confidence of a computation.
 *
 * Morning or night has to be known, too. A bare "11:55" used to be read as the morning, which is
 * the wrong chart for someone born at 11:55 at night. An hour from 1 to 12 with nothing to say
 * which half of the day is therefore `ambiguous`, and the sage is told to ask. An hour past 12,
 * midnight's 00, and a zero-padded "07:30" all read the way a 24-hour clock writes them.
 */
export function readClock(raw: string | null | undefined): StatedClock {
  const said = (raw ?? "").toLowerCase();
  const match = /(\d{1,2})[:.](\d{2})/.exec(said);
  if (!match) return { time: null, ambiguous: false };

  let hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (minutes > 59 || hours > 23) return { time: null, ambiguous: false };

  const clock = () =>
    `${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}`;

  if (hours === 0 || hours > 12) return { time: clock(), ambiguous: false };

  if (AFTERNOON.test(said)) {
    if (hours < 12) hours += 12;
  } else if (NIGHT.test(said)) {
    if (hours === 12) hours = 0;
    else if (hours >= NIGHT_BECOMES_EVENING) hours += 12;
  } else if (MORNING.test(said)) {
    if (hours === 12) hours = 0;
  } else if (!match[1].startsWith("0")) {
    return { time: null, ambiguous: true };
  }

  return { time: clock(), ambiguous: false };
}
