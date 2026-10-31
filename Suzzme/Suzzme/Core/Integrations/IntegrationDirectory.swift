import Foundation

enum IntegrationDirectorySection: String, CaseIterable, Identifiable {
    case development, productivity, projects, communication, business
    case marketing, analytics, finance, scheduling, design
    var id: String { rawValue }
    var title: String {
        switch self {
        case .development: "Development and data"
        case .productivity: "Productivity"
        case .projects: "Project management"
        case .communication: "Communication and social"
        case .business: "Business and support"
        case .marketing: "Marketing and publishing"
        case .analytics: "Analytics"
        case .finance: "Finance"
        case .scheduling: "Scheduling and meetings"
        case .design: "Design and content"
        }
    }
}

enum IntegrationDirectoryAvailability {
    case connectable, managedGoogle, limited, listedOnly
}

struct IntegrationDirectoryItem: Identifiable {
    let id: String
    let name: String
    let section: IntegrationDirectorySection
    let symbol: String
    let monogram: String
    let brand: String
    let summary: String
    let integrationID: IntegrationID?
    let availability: IntegrationDirectoryAvailability

    private static func listed(_ name: String, _ section: IntegrationDirectorySection, _ mark: String) -> Self {
        let id = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        if id == "slack" {
            return Self(id: id, name: name, section: section, symbol: "number", monogram: mark, brand: id,
                summary: "Read one channel message through your Composio connector. Replies and attachments are excluded.",
                integrationID: nil, availability: .limited)
        }
        if let recipe = ProviderReadRecipe.catalog.first(where: { $0.name == name }) {
            return Self(id: id, name: name, section: section, symbol: "network", monogram: mark, brand: id,
                        summary: "Read authorized \(name) information with a verified account and explicit scope.",
                        integrationID: recipe.id, availability: .connectable)
        }
        return Self(id: id, name: name, section: section, symbol: "app.fill", monogram: mark,
                    brand: id, summary: id == "whatsapp" ? "Reference only. WhatsApp chat access is not available in Suzzme." : "Listed in the reference catalog. Suzzme does not connect to this app in this build.",
                    integrationID: nil, availability: .listedOnly)
    }

    private static let liveConnections: [Self] = [
        .init(id: "github", name: "GitHub", section: .development, symbol: "chevron.left.forwardslash.chevron.right", monogram: "GH", brand: "github", summary: "Read-only access to repositories you allow.", integrationID: .github, availability: .connectable),
        .init(id: "notion", name: "Notion", section: .productivity, symbol: "doc.text", monogram: "N", brand: "notion", summary: "Read-only access to pages you allow.", integrationID: .notion, availability: .connectable),
        .init(id: "linear", name: "Linear", section: .projects, symbol: "circle.circle", monogram: "L", brand: "linear", summary: "Read-only access to issues you allow.", integrationID: .linear, availability: .connectable),
        .init(id: "gmail", name: "Gmail", section: .communication, symbol: "envelope.fill", monogram: "M", brand: "gmail", summary: "Selected inbox headers or on-device message summaries for your Daily Summary.", integrationID: nil, availability: .managedGoogle),
        .init(id: "linkedin", name: "LinkedIn", section: .communication, symbol: "person.crop.square", monogram: "in", brand: "linkedin", summary: "Understand only text or screenshots you explicitly share. No connected account access.", integrationID: .linkedin, availability: .limited),
        .init(id: "whatsapp", name: "WhatsApp", section: .communication, symbol: "message", monogram: "W", brand: "whatsapp", summary: "Summarize selected chats synced to WhatsApp for Mac on this device. iPhone receives the prepared Daily Summary.", integrationID: nil, availability: .limited)
    ]

    private static let referenceCatalog: [Self] = [
        listed("Airtable", .productivity, "A"),
        listed("Apaleo", .business, "A"),
        listed("Asana", .projects, "A"),
        listed("Attio", .business, "A"),
        listed("Basecamp", .projects, "B"),
        listed("Bitbucket", .development, "B"),
        listed("Blackbaud", .business, "B"),
        listed("BoldSign", .business, "B"),
        listed("Box", .productivity, "box"),
        listed("Cal.com", .scheduling, "Cal"),
        listed("Calendly", .scheduling, "C"),
        listed("Canva", .design, "C"),
        listed("Capsule CRM", .business, "C"),
        listed("ClickUp", .projects, "C"),
        listed("Confluence", .productivity, "C"),
        listed("Contentful", .design, "C"),
        listed("Crowdin", .design, "C"),
        listed("Dart", .development, "D"),
        listed("Daytona", .development, "D"),
        listed("Dialpad", .communication, "D"),
        listed("Discord", .communication, "D"),
        listed("Discord Bot", .communication, "DB"),
        listed("Dropbox", .productivity, "✣"),
        listed("Dub", .marketing, "d"),
        listed("Dynamics 365", .business, "D"),
        listed("Eventbrite", .marketing, "E"),
        listed("Excel", .productivity, "X"),
        listed("Exist", .analytics, "E"),
        listed("Facebook", .marketing, "f"),
        listed("Fathom", .scheduling, "F"),
        listed("Figma", .design, "F"),
        listed("FreeAgent", .finance, "F"),
        listed("FreshBooks", .finance, "F"),
        listed("GitLab", .development, "G"),
        listed("Gong", .business, "G"),
        listed("Google Ads", .marketing, "A"),
        listed("Google Analytics", .analytics, "A"),
        listed("Google BigQuery", .analytics, "BQ"),
        listed("Google Calendar", .scheduling, "31"),
        listed("Google Classroom", .productivity, "C"),
        listed("Google Docs", .productivity, "D"),
        listed("Google Drive", .productivity, "△"),
        listed("Google Maps", .productivity, "M"),
        listed("Google Meet", .scheduling, "M"),
        listed("Google Photos", .productivity, "P"),
        listed("Google Search Console", .analytics, "SC"),
        listed("Google Sheets", .productivity, "S"),
        listed("Google Slides", .productivity, "S"),
        listed("Google Tasks", .productivity, "✓"),
        listed("Gorgias", .business, "G"),
        listed("Greenhouse", .business, "G"),
        listed("Gumroad", .business, "G"),
        listed("Harvest", .finance, "H"),
        listed("HubSpot", .business, "H"),
        listed("Hugging Face", .development, "🤗"),
        listed("Instagram", .marketing, "◎"),
        listed("Intercom", .business, "I"),
        listed("Jira", .projects, "J"),
        listed("Kit", .marketing, "K"),
        listed("Linkhut", .productivity, "L"),
        listed("Mailchimp", .marketing, "M"),
        listed("Microsoft Teams", .communication, "T"),
        listed("Miro", .design, "M"),
        listed("Moneybird", .finance, "M"),
        listed("Mural", .design, "M"),
        listed("NotebookLM", .productivity, "N"),
        listed("Omnisend", .marketing, "O"),
        listed("OneDrive", .productivity, "☁"),
        listed("Outlook", .productivity, "O"),
        listed("PagerDuty", .development, "P"),
        listed("Pinterest", .marketing, "P"),
        listed("Pinterest Ads", .marketing, "P"),
        listed("Prisma", .development, "P"),
        listed("Productboard", .projects, "P"),
        listed("Pushbullet", .productivity, "P"),
        listed("QuickBooks", .finance, "qb"),
        listed("Reddit Ads", .marketing, "R"),
        listed("Roam", .communication, "R"),
        listed("Salesforce", .business, "S"),
        listed("Sentry", .development, "S"),
        listed("ServiceM8", .business, "S8"),
        listed("SharePoint", .productivity, "S"),
        listed("Shippo", .business, "S"),
        listed("Shopify", .business, "S"),
        listed("Slack", .communication, "#"),
        listed("Slackbot", .communication, "S"),
        listed("Splitwise", .finance, "S"),
        listed("Square", .finance, "□"),
        listed("Stack Exchange", .development, "SE"),
        listed("Stripe", .finance, "S"),
        listed("Supabase", .development, "S"),
        listed("Ticketmaster", .scheduling, "t"),
        listed("TickTick", .productivity, "✓"),
        listed("TikTok Ads", .marketing, "♪"),
        listed("Timely", .scheduling, "T"),
        listed("Todoist", .productivity, "≋"),
        listed("Trello", .projects, "T"),
        listed("Twitch", .marketing, "T"),
        listed("Typeform", .productivity, "T"),
        listed("WakaTime", .development, "W"),
        listed("Webex", .scheduling, "W"),
        listed("Wrike", .projects, "W"),
        listed("Yandex", .productivity, "Y"),
        listed("YNAB", .finance, "Y"),
        listed("YouTube", .marketing, "▶"),
        listed("Zendesk", .business, "Z"),
        listed("Zeplin", .design, "Z"),
        listed("Zoho", .business, "Z"),
        listed("Zoho Bigin", .business, "ZB"),
        listed("Zoho Books", .finance, "ZB"),
        listed("Zoho Desk", .business, "ZD"),
        listed("Zoho Inventory", .business, "ZI"),
        listed("Zoho Invoice", .finance, "ZI"),
        listed("Zoho Mail", .communication, "ZM"),
        listed("Zoom", .scheduling, "Z")
    ]

    static let catalog = (liveConnections + referenceCatalog).sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
}

