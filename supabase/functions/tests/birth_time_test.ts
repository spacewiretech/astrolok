import { assertEquals } from "jsr:@std/assert@1";

import { readClock } from "../_shared/birth_time.ts";

/**
 * A time read here is promoted onto `users.birth_time` and never overwritten by a later sentence,
 * so the chart is only as right as this is. The cases are the ways people in this app actually say
 * the hour: with AM or PM, with the Hindi word for the part of the day, or — the dangerous one —
 * with nothing at all.
 */

Deno.test("a time with AM or PM is read as said", () => {
  assertEquals(readClock("I was born at 11:55 PM."), { time: "23:55", ambiguous: false });
  assertEquals(readClock("11:55 am"), { time: "11:55", ambiguous: false });
  assertEquals(readClock("12:30 am"), { time: "00:30", ambiguous: false });
  assertEquals(readClock("12:15 pm"), { time: "12:15", ambiguous: false });
});

Deno.test("the Hindi words for the part of the day are heard, in either script", () => {
  assertEquals(readClock("raat 11:55 baje"), { time: "23:55", ambiguous: false });
  assertEquals(readClock("रात 11:55"), { time: "23:55", ambiguous: false });
  assertEquals(readClock("shaam 6:30"), { time: "18:30", ambiguous: false });
  assertEquals(readClock("सुबह 7:15"), { time: "07:15", ambiguous: false });
  assertEquals(readClock("dopahar 2:00"), { time: "14:00", ambiguous: false });
});

Deno.test("night runs past midnight, the way people say it", () => {
  assertEquals(readClock("raat 2:30 baje"), { time: "02:30", ambiguous: false });
  assertEquals(readClock("raat 12:10"), { time: "00:10", ambiguous: false });
  assertEquals(readClock("11:55 at night"), { time: "23:55", ambiguous: false });
});

Deno.test("an hour that could be either half of the day is not guessed", () => {
  for (const said of ["11:55", "I was born at 7:30", "12:00"]) {
    assertEquals(readClock(said), { time: null, ambiguous: true }, `"${said}" was guessed`);
  }
});

Deno.test("a twenty-four-hour clock needs no marker", () => {
  assertEquals(readClock("23:55"), { time: "23:55", ambiguous: false });
  assertEquals(readClock("07:30"), { time: "07:30", ambiguous: false });
  assertEquals(readClock("00:45"), { time: "00:45", ambiguous: false });
});

Deno.test("something that is not a time is neither a time nor ambiguous", () => {
  for (const said of ["around sunrise", "", "25:00", "11:75", undefined, null]) {
    assertEquals(readClock(said), { time: null, ambiguous: false }, `"${said}" was read as a time`);
  }
});
