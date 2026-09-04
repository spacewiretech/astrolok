/**
 * The two things every prompt needs to know about who it is writing for.
 *
 * Both lived at module scope in `palm-reading/index.ts` and again, identically, in
 * `face-reading/index.ts`. The chat would have been the third copy, which is one more than any
 * function this small deserves.
 */

/**
 * Whole years, computed in UTC.
 *
 * UTC throughout on purpose: `dob` is a calendar fact with no zone, and letting it drift through
 * a local-time conversion is how someone born on the 1st becomes a day younger in Kolkata.
 *
 * Null for a missing, unparseable or implausible date, so a bad row degrades into "the sage does
 * not know their age" rather than into a reading addressed to a 3,000-year-old.
 */
export function ageFrom(dob: string | null | undefined): number | null {
  if (!dob) return null;
  const born = new Date(`${dob}T00:00:00Z`);
  if (Number.isNaN(born.getTime())) return null;

  const now = new Date();
  let age = now.getUTCFullYear() - born.getUTCFullYear();
  const monthDelta = now.getUTCMonth() - born.getUTCMonth();
  if (monthDelta < 0 || (monthDelta === 0 && now.getUTCDate() < born.getUTCDate())) age -= 1;

  return age >= 0 && age < 130 ? age : null;
}

/**
 * First name only.
 *
 * The prompts address the user directly, and a full legal name reads oddly in a sentence that is
 * trying to sound like someone speaking to you.
 */
export function firstName(name: string | null | undefined): string | null {
  const first = (name ?? "").trim().split(/\s+/)[0];
  return first.length > 0 ? first : null;
}
