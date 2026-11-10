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
                summary: "Connect with Slack personal token or Composio for selected channel messages and updates.",
                integrationID: .slack, availability: .connectable)
        }
        if let recipe = ProviderReadRecipe.catalog.first(where: { $0.name == name }) {
            return Self(id: id, name: name, section: section, symbol: "network", monogram: mark, brand: id,
                        summary: "Read authorized \(name) information with a verified account and explicit scope.",
                        integrationID: recipe.id, availability: .connectable)
        }
        let directID = IntegrationID(rawValue: id)
        return Self(id: id, name: name, section: section, symbol: "app.fill", monogram: mark,
                    brand: id, summary: "Connect \(name) using a Personal Access Token or Composio Connect.",
                    integrationID: directID, availability: .connectable)
    }

    private static let liveConnections: [Self] = [
        .init(id: "apple-mail", name: "Apple Mail", section: .communication, symbol: "envelope.fill", monogram: "AM", brand: "apple-mail", summary: "Native read-only inbox access on this Mac. Zero server proxy.", integrationID: nil, availability: .connectable),
        .init(id: "apple-notes", name: "Apple Notes", section: .productivity, symbol: "note.text", monogram: "AN", brand: "apple-notes", summary: "Native on-device Apple Notes reader. Summarizes recent notes and action items locally.", integrationID: nil, availability: .connectable),
        .init(id: "apple-messages", name: "Apple Messages", section: .communication, symbol: "message.fill", monogram: "AM", brand: "apple-messages", summary: "Native on-device iMessage reader with contact resolution and conversation triage.", integrationID: nil, availability: .connectable),
        .init(id: "gmail", name: "Gmail", section: .communication, symbol: "envelope.fill", monogram: "M", brand: "gmail", summary: "Direct Google OAuth integration with on-device parsing and Keychain storage.", integrationID: .gmail, availability: .connectable),
        .init(id: "github", name: "GitHub", section: .development, symbol: "chevron.left.forwardslash.chevron.right", monogram: "GH", brand: "github", summary: "Read-only access to repositories you allow.", integrationID: .github, availability: .connectable),
        .init(id: "notion", name: "Notion", section: .productivity, symbol: "doc.text", monogram: "N", brand: "notion", summary: "Read-only access to pages you allow.", integrationID: .notion, availability: .connectable),
        .init(id: "linear", name: "Linear", section: .projects, symbol: "circle.circle", monogram: "L", brand: "linear", summary: "Read-only access to issues you allow.", integrationID: .linear, availability: .connectable),
        .init(id: "linkedin", name: "LinkedIn", section: .communication, symbol: "person.crop.square", monogram: "in", brand: "linkedin", summary: "Connect with Composio to read your own basic profile only. Feed, inbox, messages, and posting are unavailable.", integrationID: .linkedin, availability: .connectable),
        .init(id: "outlook", name: "Outlook", section: .productivity, symbol: "envelope", monogram: "O", brand: "outlook", summary: "Connect with Composio for selected inbox previews. Full threads and attachments are excluded.", integrationID: .outlook, availability: .connectable),
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
        listed("Convex", .development, "CV"),
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
        listed("Google Admin", .business, "GA"),
        listed("Google Analytics", .analytics, "A"),
        listed("Google BigQuery", .analytics, "BQ"),
        listed("Google Calendar", .scheduling, "31"),
        listed("Google Chat", .communication, "C"),
        listed("Google Classroom", .productivity, "C"),
        listed("Google Cloud Vision", .analytics, "CV"),
        listed("Google Contacts", .productivity, "C"),
        listed("Google Docs", .productivity, "D"),
        listed("Google Drive", .productivity, "△"),
        listed("Google Forms", .productivity, "F"),
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
        listed("PagerDuty", .development, "P"),
        listed("Pinterest", .marketing, "P"),
        listed("Pinterest Ads", .marketing, "P"),
        listed("PostHog", .analytics, "PH"),
        listed("Prisma", .development, "P"),
        listed("Productboard", .projects, "P"),
        listed("Pushbullet", .productivity, "P"),
        listed("QuickBooks", .finance, "qb"),
        listed("Reddit", .communication, "R"),
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
        listed("Telegram", .communication, "T"),
        listed("TikTok", .marketing, "♪"),
        listed("Twitter", .marketing, "X"),
        listed("Typeform", .productivity, "T"),
        listed("WakaTime", .development, "W"),
        listed("Webex", .scheduling, "W"),
        listed("Wrike", .projects, "W"),
        listed("Yandex", .productivity, "Y"),
        listed("YNAB", .finance, "Y"),
        listed("WhatsApp Business", .communication, "W"),
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

    /// Essential and most popular integrations featured prominently at the top of the Knowledge Sources view.
    static let featuredAppIDs: [String] = [
        "apple-notes",
        "apple-messages",
        "apple-mail",
        "gmail",
        "google-calendar",
        "whatsapp",
        "slack",
        "notion",
        "github",
        "linear",
        "figma",
        "google-drive",
        "airtable",
        "asana",
        "discord",
        "jira",
        "zoom",
        "dropbox",
        "outlook"
    ]

    static var featuredCatalog: [IntegrationDirectoryItem] {
        featuredAppIDs.compactMap { id in
            catalog.first(where: { $0.id == id })
        }
    }

    /// The 64-app integration set requested for parity with HeyClicky's catalog.
    /// These names are counted against the full directory rather than assumed enabled.
    static let requestedCatalogNames: Set<String> = Set("""
    Airtable
    Asana
    Attio
    Box
    Cal.com
    Calendly
    Canva
    ClickUp
    Confluence
    Contentful
    Convex
    Discord
    Dropbox
    Facebook
    Figma
    GitHub
    GitLab
    Gmail
    Google Admin
    Google Analytics
    Google Chat
    Google Classroom
    Google Cloud Vision
    Google Maps
    Google Search Console
    Google Ads
    Google BigQuery
    Google Calendar
    Google Contacts
    Google Docs
    Google Drive
    Google Forms
    Google Meet
    Google Photos
    Google Sheets
    Google Slides
    Google Tasks
    HubSpot
    Instagram
    Jira
    Kit
    Linear
    LinkedIn
    Miro
    Notion
    OneDrive
    Outlook
    PostHog
    Reddit
    Salesforce
    Sentry
    Shopify
    Slack
    Stack Exchange
    Stripe
    Telegram
    TikTok
    Todoist
    Trello
    Twitter
    Typeform
    WhatsApp Business
    YouTube
    Zendesk
    """.split(whereSeparator: \.isNewline).map(String.init))

    static var requestedCatalogCount: Int {
        catalog.filter { requestedCatalogNames.contains($0.name) }.count
    }
}

