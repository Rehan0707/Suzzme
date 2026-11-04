import test from 'node:test';
import assert from 'node:assert/strict';
import { googleCalendarResource, readGoogleCalendar } from './calendar-read.mjs';

const check = (condition, status = 400, message = 'Invalid request.') => {
  if (!condition) throw Object.assign(new Error(message), { status });
};
const fixedNow = Date.parse('2026-11-04T12:00:00.000Z');
const events = [{ id: 'event_123', summary: 'Design review', status: 'confirmed',
  start: { dateTime: '2026-11-04T15:00:00-05:00' }, end: { dateTime: '2026-11-04T15:30:00-05:00' } },
{ id: 'all_day', summary: 'Focus day', status: 'tentative', start: { date: '2026-11-05' }, end: { date: '2026-11-06' } }];

test('Google Calendar reads only the fixed primary calendar and 48-hour event fields', async () => {
  let endpoint;
  const text = await readGoogleCalendar(googleCalendarResource, async url => {
    endpoint = new URL(url);
    return { items: events };
  }, check, fixedNow);
  assert.equal(endpoint.origin, 'https://www.googleapis.com');
  assert.equal(endpoint.pathname, '/calendar/v3/calendars/primary/events');
  assert.deepEqual(Object.fromEntries(endpoint.searchParams), {
    timeMin: '2026-11-04T12:00:00.000Z', timeMax: '2026-11-06T12:00:00.000Z',
    maxResults: '30', singleEvents: 'true', orderBy: 'startTime',
    fields: 'items(id,summary,start,end,status),nextPageToken',
  });
  assert.match(text, /Event: Design review/);
  assert.match(text, /Start: 2026-11-04T20:00:00\.000Z/);
  assert.match(text, /Event: Focus day\nStart: 2026-11-05\nEnd: 2026-11-06/);
  assert.doesNotMatch(text, /attendees|description|location|event_123/);
});

test('Google Calendar rejects alternate URLs and malformed event fields before returning content', async () => {
  let requested = false;
  await assert.rejects(() => readGoogleCalendar('https://evil.example/calendar', async () => {
    requested = true; return { items: [] };
  }, check, fixedNow), error => error.status === 422);
  assert.equal(requested, false);
  for (const items of [
    [{ id: 'bad id', summary: 'x', status: 'confirmed', start: { date: '2026-11-05' }, end: { date: '2026-11-06' } }],
    [{ id: 'event', summary: 'x', status: 'confirmed', start: { date: 'tomorrow' }, end: { date: '2026-11-06' } }],
    [{ id: 'event', summary: 'x', status: 'confirmed', start: { date: '2026-11-06' }, end: { date: '2026-11-05' } }],
    [{ id: 'event', summary: { text: 'unexpected' }, status: 'confirmed', start: { date: '2026-11-05' }, end: { date: '2026-11-06' } }],
    [{ id: 'event', summary: 'x', status: 'unknown', start: { date: '2026-11-05' }, end: { date: '2026-11-06' } }],
  ]) {
    await assert.rejects(() => readGoogleCalendar(googleCalendarResource, async () => ({ items }), check, fixedNow),
      error => error.status === 502);
  }
});

test('Google Calendar empty and paginated responses are explicit and bounded', async () => {
  const empty = await readGoogleCalendar(googleCalendarResource, async () => ({ items: [] }), check, fixedNow);
  assert.match(empty, /No events in the next 48 hours/);
  const partial = await readGoogleCalendar(googleCalendarResource, async () => ({ items: events, nextPageToken: 'next' }), check, fixedNow);
  assert.match(partial, /Partial result: more events exist beyond the 30-event read limit/);
});
