// Stateless MCP endpoint over the existing owner-scoped Composio read recipes.
// Discovery is descriptive only: execution always rechecks the selected account.
export const protocolVersion = '2025-11-25';
const versions = new Set([protocolVersion, '2025-06-18', '2025-03-26']);
const recipes = Object.freeze({
  gmail: ['suzzme_read_gmail_inbox', 'Read recent Gmail inbox previews'],
  googlecalendar: ['suzzme_read_google_calendar', 'Read primary Google Calendar event titles and times'],
  outlook: ['suzzme_read_outlook_inbox', 'Read recent Outlook inbox previews'],
  github: ['suzzme_read_github_issue', 'Read one selected issue or today’s commits and pull requests from one selected repository'],
  linkedin: ['suzzme_read_linkedin_profile', 'Read your own basic LinkedIn profile only'],
  slack: ['suzzme_read_slack_message', 'Read one selected Slack channel message'],
  notion: ['suzzme_read_notion_page', 'Read top-level text from one selected Notion page'],
});
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const keys = (value, allowed) => object(value) && Object.keys(value).every(key => allowed.includes(key));
const fault = (id, code, message) => ({ jsonrpc: '2.0', id, error: { code, message } });

export async function handleMCP(message, configuredServices, read) {
  const id = typeof message?.id === 'string' && message.id.length <= 128
    || Number.isSafeInteger(message?.id) ? message.id : null;
  if (!keys(message, ['jsonrpc', 'id', 'method', 'params']) || message.jsonrpc !== '2.0'
    || typeof message.method !== 'string' || (Object.hasOwn(message, 'id') && id === null)) {
    return fault(null, -32600, 'Invalid MCP request.');
  }
  const params = message.params ?? {};
  if (!object(params)) return fault(id, -32602, 'Invalid parameters.');
  // Notifications never execute tools, even if their name resembles a request.
  if (!Object.hasOwn(message, 'id')) return { accepted: true };
  const result = value => ({ jsonrpc: '2.0', id, result: value });
  if (message.method === 'initialize') {
    if (typeof params.protocolVersion !== 'string' || !object(params.capabilities)
      || typeof params.clientInfo?.name !== 'string' || typeof params.clientInfo?.version !== 'string') {
      return fault(id, -32602, 'Invalid initialization.');
    }
    return result({ protocolVersion: versions.has(params.protocolVersion) ? params.protocolVersion : protocolVersion,
      capabilities: { tools: { listChanged: false } }, serverInfo: { name: 'suzzme-composio', version: '1.0.0' } });
  }
  if (message.method === 'ping') return result({});
  const enabled = Object.entries(recipes).filter(([service]) => configuredServices.includes(service));
  if (message.method === 'tools/list') {
    if (!keys(params, ['_meta'])) return fault(id, -32602, 'Pagination is not supported.');
    return result({ tools: enabled.map(([, [name, description]]) => ({ name, description,
      inputSchema: { type: 'object', additionalProperties: false, required: ['accountID', 'resource'],
        properties: { accountID: { type: 'string', minLength: 1, maxLength: 160 },
          resource: { type: 'string', minLength: 1, maxLength: 512 },
          now: { type: 'string', minLength: 1, maxLength: 64 },
          timeZone: { type: 'string', minLength: 1, maxLength: 128 } } },
      annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: true },
    })) });
  }
  if (message.method !== 'tools/call') return fault(id, -32601, 'Unsupported MCP method.');
  const recipe = enabled.find(([, [name]]) => name === params.name);
  if (!keys(params, ['name', 'arguments', '_meta']) || !recipe
    || !keys(params.arguments, ['accountID', 'resource', 'now', 'timeZone'])
    || typeof params.arguments.accountID !== 'string' || !/^[A-Za-z0-9_-]{1,160}$/.test(params.arguments.accountID)
    || typeof params.arguments.resource !== 'string' || !params.arguments.resource.length || params.arguments.resource.length > 512
    || (params.arguments.now !== undefined && (typeof params.arguments.now !== 'string' || params.arguments.now.length > 64))
    || (params.arguments.timeZone !== undefined && (typeof params.arguments.timeZone !== 'string' || params.arguments.timeZone.length > 128))
    || (params.arguments.now === undefined) !== (params.arguments.timeZone === undefined)) {
    return fault(id, -32602, 'Choose a supported read tool, account and source link.');
  }
  try {
    const excerpt = await read({ ...params.arguments, service: recipe[0] });
    return result({ content: [{ type: 'text', text: JSON.stringify(excerpt) }], structuredContent: excerpt, isError: false });
  } catch (error) {
    // Do not expose provider errors, secrets or personal content through diagnostics.
    const status = [400, 401, 403, 409, 413, 422, 429].includes(error?.status) ? error.status : 502;
    return result({ isError: true, content: [{ type: 'text', text: 'The selected source could not be read.' }],
      structuredContent: { error: { status } } });
  }
}

export function supportsProtocol(value) { return value === undefined || value === null || versions.has(value); }
