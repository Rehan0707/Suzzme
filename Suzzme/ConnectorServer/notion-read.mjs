// A selected-page recipe, never a caller-controlled API proxy. No recursion,
// workspace search, file downloads, database queries or writes are performed.
export async function readNotion(resource, read, check) {
  const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
  const normalized = value => uuid(value) ? value.toLowerCase() : null;
  const match = /^https:\/\/(?:www\.notion\.so|notion\.so|[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.notion\.site)\/(?:[A-Za-z0-9_-]+-)?([0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i.exec(resource);
  check(match, 422, 'Choose a Notion page link containing its page ID, without a query or fragment.');
  const compact = match[1].replaceAll('-', '').toLowerCase();
  const id = compact.replace(/^(.{8})(.{4})(.{4})(.{4})(.{12})$/, '$1-$2-$3-$4-$5');
  const instant = value => typeof value === 'string'
    && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value) && Number.isFinite(Date.parse(value));
  function richText(items) {
    check(Array.isArray(items) && items.length <= 100, 502, 'Unexpected Notion text format.');
    return items.map(item => {
      check(item && typeof item.type === 'string', 502, 'Unexpected Notion text format.');
      if (item.type !== 'text') return '[Non-text mention or equation omitted]';
      check(typeof item.plain_text === 'string' && typeof item.text?.content === 'string'
        && item.plain_text === item.text.content, 502, 'Unexpected Notion text format.');
      return item.plain_text;
    }).join('');
  }
  function metadata(page) {
    check(page?.object === 'page' && normalized(page.id) === id
      && page.archived === false && page.in_trash === false
      && instant(page.created_time) && instant(page.last_edited_time)
      && Date.parse(page.created_time) <= Date.parse(page.last_edited_time)
      && page.properties && typeof page.properties === 'object' && !Array.isArray(page.properties),
    422, 'The selected Notion page is unavailable or could not be verified.');
    const titles = Object.values(page.properties).filter(value => value?.type === 'title');
    check(titles.length === 1, 502, 'The Notion page title could not be verified.');
    const title = richText(titles[0].title);
    check(!/[\r\n\0]/.test(title), 422, 'The selected Notion page title is not supported.');
    return { title, created: page.created_time, edited: page.last_edited_time };
  }
  const endpoint = 'https://api.notion.com/v1/pages/' + id;
  const page = metadata(await read(endpoint));
  const children = await read('https://api.notion.com/v1/blocks/' + id + '/children?page_size=100');
  check(children?.object === 'list' && Array.isArray(children.results) && children.results.length <= 100
    && typeof children.has_more === 'boolean'
    && (children.has_more ? typeof children.next_cursor === 'string' && children.next_cursor.length > 0 : children.next_cursor === null),
  502, 'Unexpected Notion page content format.');
  const supported = new Set(['paragraph', 'heading_1', 'heading_2', 'heading_3', 'bulleted_list_item',
    'numbered_list_item', 'to_do', 'toggle', 'quote', 'callout', 'code']);
  const lines = []; const ids = new Set(); let hasText = false;
  for (const block of children.results) {
    check(block?.object === 'block' && uuid(block.id) && !ids.has(block.id.toLowerCase())
      && block.parent?.type === 'page_id' && normalized(block.parent.page_id) === id
      && block.archived === false && block.in_trash === false && typeof block.has_children === 'boolean'
      && typeof block.type === 'string', 502, 'Unexpected Notion block identity.');
    ids.add(block.id.toLowerCase());
    if (!supported.has(block.type)) { lines.push('[Unsupported block omitted]'); continue; }
    const content = richText(block[block.type]?.rich_text);
    if (block.type === 'to_do') check(typeof block.to_do.checked === 'boolean', 502, 'Unexpected Notion task state.');
    const prefix = block.type === 'to_do' ? (block.to_do.checked ? '[Done] ' : '[To do] ')
      : block.type.startsWith('heading_') ? 'Heading: ' : block.type.endsWith('list_item') ? 'List item: ' : '';
    if (content.trim()) {
      hasText ||= block[block.type].rich_text.some(item => item.type === 'text' && item.plain_text.trim().length > 0);
      lines.push(prefix + content);
    }
    if (block.has_children) lines.push('[Nested content omitted]');
  }
  check(hasText, 422, 'This page has no supported top-level text. Nested pages and files are not read.');
  if (children.has_more) lines.push('[Additional top-level blocks omitted; first 100 only]');
  // A second metadata read rejects edits or removal during retrieval. This is
  // best-effort consistency, not an atomic Notion snapshot.
  check(JSON.stringify(metadata(await read(endpoint))) === JSON.stringify(page), 422,
    'The Notion page changed while reading. Try again.');
  return 'Title: ' + page.title + '\nCreated: ' + page.created + '\nLast edited: ' + page.edited
    + '\nSelected page excerpt (top-level text only; nested content, non-text mentions, files, database content and unsupported blocks excluded):\n'
    + lines.join('\n');
}
