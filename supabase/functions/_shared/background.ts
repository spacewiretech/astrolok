/**
 * Hands work to the runtime so the response can go now and the work can finish after it.
 *
 * `EdgeRuntime.waitUntil` keeps the isolate alive past the response — how the cron-driven workers
 * answer pg_cron within its timeout and still run a batch, and how the webhook's notification
 * hooks stay off the path Cashfree is waiting on. Where it does not exist (`deno check`, a local
 * run, a test) the work is awaited instead, so nothing is silently dropped. The same shape as
 * `send` in `mixpanel.ts`.
 *
 * The task's own failure is logged and swallowed: whatever a background task was doing, it must
 * never surface as an unhandled rejection that kills the isolate mid-batch.
 */
export function inBackground(label: string, task: Promise<unknown>): Promise<void> {
  const guarded = task.then(() => {}, (error) => console.error(`${label} failed`, error));

  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (p: Promise<unknown>) => void } })
    .EdgeRuntime;

  if (typeof runtime?.waitUntil === "function") {
    runtime.waitUntil(guarded);
    return Promise.resolve();
  }
  return guarded;
}

/** Runs [worker] over [items], at most [concurrency] at a time, stopping new starts past [deadline]. */
export async function eachBounded<T>(
  items: T[],
  { concurrency, deadline }: { concurrency: number; deadline: number },
  worker: (item: T) => Promise<void>,
): Promise<number> {
  let next = 0;
  let done = 0;
  const lane = async () => {
    while (next < items.length && Date.now() < deadline) {
      const item = items[next++];
      try {
        await worker(item);
      } catch (error) {
        console.error("bounded worker item failed", error);
      }
      done += 1;
    }
  };
  await Promise.all(Array.from({ length: Math.max(1, concurrency) }, lane));
  return done;
}
