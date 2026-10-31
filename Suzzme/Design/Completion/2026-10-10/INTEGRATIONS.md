# Integration inventory — 10 October 2026

Generated from the current 121-item directory and 24 existing recipes. This is an implementation inventory, not live API acceptance.

27 implemented provider reads, Gmail separately, LinkedIn screen-only, 92 catalog-only entries (including intentionally excluded WhatsApp). No live external account accepted in this pass. **Individual feasibility review of the 92 catalog-only APIs remains unfinished.**

| Provider | Implementation | Authentication / next requirement | Summary intake |
|---|---|---|---|
| Airtable | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| Apaleo | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Asana | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| Attio | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Basecamp | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Bitbucket | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Blackbaud | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| BoldSign | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Box | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Cal.com | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Calendly | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Canva | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Capsule CRM | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| ClickUp | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| Confluence | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Contentful | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| Crowdin | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Dart | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Daytona | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Dialpad | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Discord | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Discord Bot | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Dropbox | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Dub | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Dynamics 365 | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Eventbrite | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| Excel | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Exist | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Facebook | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Fathom | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Figma | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| FreeAgent | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| FreshBooks | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| GitHub | IMPLEMENTED — reviewed resource reads | Scoped personal token required | EXPLICIT OPT-IN — selected allowed issue/PR/page URLs |
| GitLab | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| Gmail | IMPLEMENTED — inbox headers only | Google client IDs still placeholders | EXPLICIT SOURCE OPT-IN |
| Gong | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Google Ads | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Google Analytics | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google BigQuery | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google Calendar | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google Classroom | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google Docs | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google Drive | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google Maps | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Google Meet | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google Photos | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Google Search Console | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google Sheets | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google Slides | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Google Tasks | IMPLEMENTED — bounded request-local reads | Registered Google OAuth required | UNAVAILABLE |
| Gorgias | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Greenhouse | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Gumroad | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Harvest | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| HubSpot | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Hugging Face | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Instagram | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Intercom | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Jira | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Kit | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Linear | IMPLEMENTED — reviewed resource reads | Scoped personal token required | EXPLICIT OPT-IN — selected allowed issue/PR/page URLs |
| LinkedIn | LIMITED — explicitly shared screen only | No account connector | UNAVAILABLE |
| Linkhut | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Mailchimp | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Microsoft Teams | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Miro | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Moneybird | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Mural | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| NotebookLM | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Notion | IMPLEMENTED — reviewed resource reads | Scoped personal token required | EXPLICIT OPT-IN — selected allowed issue/PR/page URLs |
| Omnisend | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| OneDrive | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Outlook | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| PagerDuty | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Pinterest | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Pinterest Ads | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Prisma | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Productboard | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Pushbullet | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| QuickBooks | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Reddit Ads | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Roam | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Salesforce | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Sentry | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| ServiceM8 | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| SharePoint | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Shippo | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Shopify | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Slack | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Slackbot | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Splitwise | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Square | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Stack Exchange | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Stripe | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Supabase | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Ticketmaster | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| TickTick | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| TikTok Ads | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Timely | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Todoist | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| Trello | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Twitch | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Typeform | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| WakaTime | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| Webex | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| WhatsApp | INTENTIONALLY EXCLUDED — no chats/contacts/messages | Unavailable | UNAVAILABLE |
| Wrike | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Yandex | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| YNAB | IMPLEMENTED — bounded request-local reads | User-managed personal credential required | UNAVAILABLE |
| YouTube | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zendesk | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zeplin | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zoho | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zoho Bigin | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zoho Books | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zoho Desk | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zoho Inventory | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zoho Invoice | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zoho Mail | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |
| Zoom | CATALOG ONLY — no connector | Unavailable | UNAVAILABLE |

The JSON companion records every entry's review state and existing recipe documentation URL. Catalog-only does not mean the provider has no API; it means Suzzme has no implemented connector. No generic Connect button is enabled for these entries.

Selected official checks: [Contentful read-only CMA scopes](https://www.contentful.com/developers/docs/references/content-management-api/access-tokens/), [Google Meet records](https://developers.google.com/workspace/meet/api/reference/rest/v2/conferenceRecords/list), [BigQuery datasets](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/datasets/list), [YNAB API](https://api.ynab.com/). These checks do not accept real account behavior.
