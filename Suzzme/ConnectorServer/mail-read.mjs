// Fixed, read-only mailbox recipes. The caller cannot supply provider endpoints or queries.
export const mailboxResources = Object.freeze({
  gmail: 'https://mail.google.com/mail/u/0/',
  outlook: 'https://outlook.office.com/mail/',
});
export async function readMailbox(service, resource, read, check, now = Date.now()) {
  check(resource === mailboxResources[service], 422, 'Choose the supported recent inbox source.');
  const clean = value => String(value ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim();
  const floor = now - 86400000;
  const messages = [];
  let limited = false;
  if (service === 'gmail') {
    const query = new URLSearchParams({q: `in:inbox after:${Math.floor(floor / 1000)}`, maxResults: '20'});
    const listing = await read('https://gmail.googleapis.com/gmail/v1/users/me/messages?' + query);
    check(listing.messages == null || Array.isArray(listing.messages), 502, 'Unexpected Gmail response.');
    limited = Boolean(listing.nextPageToken);
    for (const item of (listing.messages ?? []).slice(0, 20)) {
      check(typeof item.id === 'string' && /^[a-f0-9]{1,64}$/i.test(item.id), 502, 'Unexpected message identity.');
      const message = await read(`https://gmail.googleapis.com/gmail/v1/users/me/messages/${item.id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From`);
      const time = Number(message.internalDate);
      check(message.id === item.id && Number.isFinite(time) && Array.isArray(message.payload?.headers), 502, 'Unexpected Gmail message.');
      if (time < floor || time > now) continue;
      const header = name => message.payload.headers.find(h => h.name?.toLowerCase() === name)?.value;
      messages.push({time, subject: header('subject'), sender: header('from'), preview: message.snippet});
    }
  } else {
    check(service === 'outlook', 422, 'Unsupported mailbox.');
    const query = new URLSearchParams({'$top': '20', '$select': 'id,subject,from,receivedDateTime,bodyPreview',
      '$filter': `receivedDateTime ge ${new Date(floor).toISOString()}`, '$orderby': 'receivedDateTime desc'});
    const listing = await read('https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?' + query);
    check(Array.isArray(listing.value), 502, 'Unexpected Outlook response.');
    limited = Boolean(listing['@odata.nextLink']);
    for (const message of listing.value.slice(0, 20)) {
      const time = Date.parse(message.receivedDateTime);
      check(Number.isFinite(time), 502, 'Unexpected message date.');
      if (time < floor || time > now) continue;
      messages.push({time, subject: message.subject, sender: message.from?.emailAddress?.address, preview: message.bodyPreview});
    }
  }
  let text = 'Recent inbox · last 24 hours. Bounded previews only; attachments and full threads excluded.\n';
  for (const item of messages.sort((a,b) => b.time - a.time)) {
    const line = `${new Date(item.time).toISOString()} | ${clean(item.sender).slice(0,80)} | ${clean(item.subject).slice(0,100)} | ${clean(item.preview).slice(0,400)}\n`;
    if (text.length + line.length > 4250) { limited = true; break; }
    text += line;
  }
  if (!messages.length) text += 'No inbox messages in this window.\n';
  if (limited) text += 'Coverage is partial; more messages may exist.\n';
  return text;
}
