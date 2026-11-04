// Fixed, read-only Google Calendar recipe. The caller can choose no endpoint,
// calendar ID, date window, fields, ordering, or number of returned events.
export const googleCalendarResource = 'https://calendar.google.com/calendar/u/0/r';
const maximumEvents = 30;
const clean = value => String(value ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim();

function eventTime(value, check) {
  check(value && typeof value === 'object' && !Array.isArray(value), 502, 'Unexpected calendar time.');
  if (typeof value.date === 'string') {
    check(/^\d{4}-\d{2}-\d{2}$/.test(value.date)
      && Number.isFinite(Date.parse(value.date + 'T00:00:00Z')), 502, 'Unexpected calendar date.');
    return value.date;
  }
  check(typeof value.dateTime === 'string' && value.dateTime.length <= 64
    && Number.isFinite(Date.parse(value.dateTime)), 502, 'Unexpected calendar time.');
  return new Date(Date.parse(value.dateTime)).toISOString();
}

export async function readGoogleCalendar(resource, read, check, now = Date.now()) {
  check(resource === googleCalendarResource, 422, 'Choose the supported primary Google Calendar source.');
  check(Number.isFinite(now), 400, 'Invalid read window.');
  const query = new URLSearchParams({
    timeMin: new Date(now).toISOString(),
    timeMax: new Date(now + 48 * 60 * 60 * 1000).toISOString(),
    maxResults: String(maximumEvents),
    singleEvents: 'true',
    orderBy: 'startTime',
    fields: 'items(id,summary,start,end,status),nextPageToken',
  });
  const data = await read('https://www.googleapis.com/calendar/v3/calendars/primary/events?' + query);
  check(data && typeof data === 'object' && !Array.isArray(data)
    && (data.items == null || Array.isArray(data.items))
    && (!data.items || data.items.length <= maximumEvents), 502, 'Unexpected Google Calendar response.');

  const lines = ['Google Calendar · primary · next 48 hours. Read-only event titles and times.'];
  for (const event of data.items ?? []) {
    check(event && typeof event === 'object' && !Array.isArray(event)
      && typeof event.id === 'string' && /^[A-Za-z0-9_@.-]{1,256}$/.test(event.id)
      && ['confirmed', 'tentative', 'cancelled'].includes(event.status), 502, 'Unexpected calendar event.');
    const start = eventTime(event.start, check);
    const end = eventTime(event.end, check);
    check(Date.parse(end) >= Date.parse(start), 502, 'Unexpected calendar event range.');
    check(event.summary == null || (typeof event.summary === 'string' && event.summary.length <= 4096),
      502, 'Unexpected calendar event title.');
    const title = clean(event.summary).slice(0, 240) || 'Untitled event';
    lines.push(`Event: ${title}\nStart: ${start}\nEnd: ${end}\nStatus: ${event.status}`);
  }
  if (!(data.items ?? []).length) lines.push('No events in the next 48 hours.');
  if (data.nextPageToken) lines.push('Partial result: more events exist beyond the 30-event read limit.');
  const text = lines.join('\n');
  check(text.length <= 4500 && !text.includes('\0'), 413, 'Calendar source is too large.');
  return text;
}
