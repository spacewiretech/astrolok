/**
 * The receiving end of the daily marketing push.
 *
 * Lives in the marketing spreadsheet, not in this repo's deploy: paste it into
 * Extensions > Apps Script on the sheet itself. It is kept here so the two halves of the
 * integration can be read together — the other half is
 * supabase/migrations/20260922000001_daily_metrics.sql, which POSTs
 *
 *   { "report_date": "2026-09-21", "signups": 42, "trials": 9, "renewals": 5, "secret": "..." }
 *
 * once a morning at 09:00 IST.
 *
 * ---------------------------------------------------------------- setup
 *
 * 1. Extensions > Apps Script, paste this in, save.
 * 2. Project Settings > Script Properties: add METRICS_SECRET with a long random value.
 * 3. Run `setup` once from the editor. It grants the permissions and prints whether the
 *    headers below were all found — do this before deploying, so a typo in COLUMNS surfaces
 *    here rather than as a silently missing column at nine tomorrow morning.
 * 4. Deploy > New deployment > Web app.
 *      Execute as: Me.   Who has access: Anyone.
 *    "Anyone" is what lets a database with no Google account post at all; the secret in step 2
 *    is what stops anyone else. Never remove it.
 * 5. Copy the /exec URL into app_config.metrics_sheet_url, and the same secret into
 *    app_config.metrics_sheet_secret.
 *
 * Re-deploying after an edit needs Deploy > Manage deployments > edit > New version. A plain
 * save does not change what the /exec URL serves, which is the usual reason a fix appears to
 * have done nothing.
 */

// Which sheet to write. Empty string means the first tab.
var SHEET_NAME = '';

// The row the headers are on. Data is assumed to start directly below it.
var HEADER_ROW = 1;

// Payload field -> the exact header text above the column it belongs in. Matching on the header
// rather than on a column letter is what lets the layout be rearranged, or a column inserted in
// the middle, without touching this script. Case and surrounding spaces are ignored.
var COLUMNS = {
  report_date: 'Date',
  signups: 'Signups',
  trials: 'Trials',
  renewals: 'Subscription Renewed'
};

function doPost(e) {
  var body;
  try {
    body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
  } catch (err) {
    return reply_({ ok: false, error: 'body is not JSON' });
  }

  var expected = PropertiesService.getScriptProperties().getProperty('METRICS_SECRET');
  if (!expected) return reply_({ ok: false, error: 'METRICS_SECRET is not set on the script' });
  if (body.secret !== expected) return reply_({ ok: false, error: 'bad secret' });

  if (!body.report_date) return reply_({ ok: false, error: 'no report_date' });

  // Two deliveries for the same date must not become two rows, so the whole read-then-write is
  // taken under a lock. Without it a retry arriving while the first is still searching finds no
  // matching date either, and both append.
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(30000)) return reply_({ ok: false, error: 'busy' });

  try {
    return reply_(writeRow_(body));
  } catch (err) {
    return reply_({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

/**
 * Every reply is JSON, so a rejected post shows up as a readable reason in `net._http_response`
 * rather than as Apps Script's own HTML error page.
 */
function reply_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}

/** Upserts one day. Returns what happened, which is echoed back to pg_net. */
function writeRow_(body) {
  var sheet = targetSheet_();
  var tz = sheet.getParent().getSpreadsheetTimeZone();
  var index = headerIndex_(sheet);

  var missing = Object.keys(COLUMNS).filter(function (field) {
    return index[field] === undefined;
  });
  if (missing.length) {
    return {
      ok: false,
      error: 'no column headed ' + missing.map(function (f) { return '"' + COLUMNS[f] + '"'; }).join(', ')
    };
  }

  var dateCol = index.report_date;
  var firstDataRow = HEADER_ROW + 1;
  var lastRow = sheet.getLastRow();

  // The date column as it stands, normalised to yyyy-MM-dd so a cell holding a real Date and a
  // payload holding a string compare equal.
  var existing = [];
  if (lastRow >= firstDataRow) {
    existing = sheet.getRange(firstDataRow, dateCol, lastRow - firstDataRow + 1, 1)
      .getValues()
      .map(function (row) { return dateKey_(row[0], tz); });
  }

  var target = existing.indexOf(String(body.report_date).trim());
  var row = target >= 0 ? firstDataRow + target : Math.max(lastRow + 1, firstDataRow);

  // Written cell by cell rather than as one range, because the columns need not be adjacent and
  // anything between them belongs to whoever designed the sheet.
  sheet.getRange(row, dateCol).setValue(asDate_(body.report_date));
  sheet.getRange(row, index.signups).setValue(numberOr_(body.signups));
  sheet.getRange(row, index.trials).setValue(numberOr_(body.trials));
  sheet.getRange(row, index.renewals).setValue(numberOr_(body.renewals));

  return { ok: true, row: row, action: target >= 0 ? 'updated' : 'appended', date: body.report_date };
}

function targetSheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = SHEET_NAME ? ss.getSheetByName(SHEET_NAME) : ss.getSheets()[0];
  if (!sheet) throw new Error('no sheet named "' + SHEET_NAME + '"');
  return sheet;
}

/** { payloadField: 1-based column } for every header this script recognises. */
function headerIndex_(sheet) {
  var width = sheet.getLastColumn();
  var headers = width
    ? sheet.getRange(HEADER_ROW, 1, 1, width).getDisplayValues()[0].map(normalise_)
    : [];

  var index = {};
  Object.keys(COLUMNS).forEach(function (field) {
    var at = headers.indexOf(normalise_(COLUMNS[field]));
    if (at >= 0) index[field] = at + 1;
  });
  return index;
}

function normalise_(v) {
  return String(v == null ? '' : v).trim().toLowerCase();
}

/** A date cell, however it is stored or formatted, as yyyy-MM-dd. */
function dateKey_(value, tz) {
  if (value instanceof Date) return Utilities.formatDate(value, tz, 'yyyy-MM-dd');
  return String(value == null ? '' : value).trim();
}

/**
 * A real Date rather than the ISO string, so the sheet's own date formatting and any chart or
 * pivot reading the column keep working. Built from the parts: `new Date('2026-09-21')` is
 * parsed as UTC midnight and lands on the 20th for anyone west of London.
 */
function asDate_(iso) {
  var parts = String(iso).split('-');
  if (parts.length !== 3) return iso;
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
}

/** Zero is a real answer and must be written; a missing field must not become one. */
function numberOr_(v) {
  return v === null || v === undefined || v === '' ? '' : Number(v);
}

/**
 * Run once from the editor, before deploying. Grants the permissions the web app needs and
 * reports whether every header in COLUMNS was actually found.
 */
function setup() {
  var sheet = targetSheet_();
  var index = headerIndex_(sheet);

  Object.keys(COLUMNS).forEach(function (field) {
    var col = index[field];
    Logger.log(
      col
        ? '"' + COLUMNS[field] + '" -> column ' + sheet.getRange(1, col).getA1Notation().replace(/\d+/, '')
        : 'NOT FOUND: no column headed "' + COLUMNS[field] + '" on row ' + HEADER_ROW
    );
  });

  Logger.log(
    PropertiesService.getScriptProperties().getProperty('METRICS_SECRET')
      ? 'METRICS_SECRET is set.'
      : 'METRICS_SECRET is NOT set — add it under Project Settings > Script Properties.'
  );
}
