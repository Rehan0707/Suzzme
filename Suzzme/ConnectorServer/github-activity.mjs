const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const bounded = (value, maximum) => [...value].slice(0, maximum).join('');

function zonedParts(instant, timeZone) {
  const values = new Intl.DateTimeFormat('en-US', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
  }).formatToParts(instant);
  return Object.fromEntries(values.filter(part => part.type !== 'literal').map(part => [part.type, Number(part.value)]));
}

function localDayStart(year, month, day, timeZone) {
  const target = Date.UTC(year, month - 1, day);
  let candidate = target;
  // Resolve the offset at local midnight, including DST changes, without
  // assuming the device's timezone matches the connector host's timezone.
  for (let attempt = 0; attempt < 4; attempt++) {
    const parts = zonedParts(new Date(candidate), timeZone);
    const represented = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute, parts.second);
    const next = target - (represented - candidate);
    if (next === candidate) break;
    candidate = next;
  }
  return candidate;
}

export function githubTodayWindow(nowValue, timeZone, serverNow = Date.now()) {
  if (typeof nowValue !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/.test(nowValue)
    || typeof timeZone !== 'string' || !timeZone || timeZone.length > 128) return null;
  const now = Date.parse(nowValue);
  if (!Number.isFinite(now) || Math.abs(now - serverNow) > 5 * 60_000) return null;
  try {
    const current = zonedParts(new Date(now), timeZone);
    const start = localDayStart(current.year, current.month, current.day, timeZone);
    const nextDate = new Date(Date.UTC(current.year, current.month - 1, current.day + 1));
    const end = localDayStart(nextDate.getUTCFullYear(), nextDate.getUTCMonth() + 1, nextDate.getUTCDate(), timeZone);
    return {
      localDate: `${String(current.year).padStart(4, '0')}-${String(current.month).padStart(2, '0')}-${String(current.day).padStart(2, '0')}`,
      timeZone, start: new Date(start), end: new Date(end),
    };
  } catch { return null; }
}

function dateInWindow(value, window) {
  if (typeof value !== 'string') return false;
  const time = Date.parse(value);
  return Number.isFinite(time) && time >= window.start.getTime() && time < window.end.getTime();
}

function firstLine(value, maximum) {
  if (typeof value !== 'string' || value.includes('\0')) return '';
  return bounded(value.split(/\r?\n/, 1)[0].trim(), maximum);
}

export function githubDailyActivityText({ owner, repository, window, commits, pullRequests }) {
  if (!/^[A-Za-z0-9_-]{1,39}$/.test(owner) || !/^[A-Za-z0-9_.-]{1,100}$/.test(repository)
    || ['.', '..'].includes(repository) || !window || !Array.isArray(commits) || !Array.isArray(pullRequests)) return null;
  const slug = `${owner.toLowerCase()}/${repository.toLowerCase()}`;
  const validCommits = [];
  let malformed = false;
  for (const item of commits) {
    const sha = item?.sha;
    const committedAt = item?.commit?.committer?.date ?? item?.commit?.author?.date;
    const message = firstLine(item?.commit?.message, 120);
    if (!/^[0-9a-f]{40}$/i.test(sha ?? '') || !message || !dateInWindow(committedAt, window)) {
      if (item && dateInWindow(committedAt, window)) malformed = true;
      continue;
    }
    validCommits.push({ sha: sha.toLowerCase(), message, committedAt,
      url: `https://github.com/${slug}/commit/${sha.slice(0, 7).toLowerCase()}` });
  }

  const validPulls = [];
  for (const item of pullRequests) {
    if (!object(item)) { malformed = true; continue; }
    const dates = [item.merged_at, item.closed_at, item.updated_at, item.created_at].filter(value => dateInWindow(value, window));
    if (!dates.length) continue;
    const title = firstLine(item.title, 120);
    if (!Number.isSafeInteger(item.number) || item.number < 1 || !title || !['open', 'closed'].includes(item.state)) {
      malformed = true; continue;
    }
    const activityAt = dates.sort((a, b) => Date.parse(b) - Date.parse(a))[0];
    validPulls.push({ number: item.number, title, state: item.state, merged: typeof item.merged_at === 'string', activityAt,
      url: `https://github.com/${slug}/pull/${item.number}` });
  }

  validCommits.sort((a, b) => Date.parse(b.committedAt) - Date.parse(a.committedAt));
  validPulls.sort((a, b) => Date.parse(b.activityAt) - Date.parse(a.activityAt));
  const truncated = malformed || commits.length >= 100 || pullRequests.length >= 100
    || validCommits.length > 4 || validPulls.length > 4;
  const payload = {
    kind: 'github-daily-activity', repository: slug, localDate: window.localDate, timeZone: window.timeZone,
    truncated, commits: validCommits.slice(0, 4), pullRequests: validPulls.slice(0, 4),
  };
  const text = JSON.stringify(payload);
  return Buffer.byteLength(text) <= 4_500 ? text : null;
}

export function githubQueryParameters(window) {
  return [
    { name: 'since', value: window.start.toISOString(), in: 'query' },
    { name: 'until', value: window.end.toISOString(), in: 'query' },
    { name: 'per_page', value: '100', in: 'query' },
  ];
}

export function githubPullRequestParameters() {
  return [
    { name: 'state', value: 'all', in: 'query' },
    { name: 'sort', value: 'updated', in: 'query' },
    { name: 'direction', value: 'desc', in: 'query' },
    { name: 'per_page', value: '100', in: 'query' },
  ];
}
