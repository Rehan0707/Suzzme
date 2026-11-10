import Foundation
#if os(macOS)
import AppKit
#endif

/// Lightweight app-specific context adapted from OpenClicky's app skill system.
/// Enriches voice and companion reasoning with deep layout, concepts, shortcuts,
/// and workflows whenever a recognized application is active on macOS.
struct SuzzmeAppSkillWorkflow: Equatable, Sendable {
    let name: String
    let steps: [String]
}

struct SuzzmeAppSkillContext: Equatable, Sendable {
    let appName: String
    let bundleIdentifier: String
    let tagline: String
    let systemPrompt: String
    let concepts: [String]
    let workflows: [SuzzmeAppSkillWorkflow]

    var promptFragment: String {
        let conceptText = concepts.map { "- \($0)" }.joined(separator: "\n")
        let workflowText = workflows.map { workflow in
            let steps = workflow.steps.enumerated().map { index, step in
                "  \(index + 1). \(step)"
            }.joined(separator: "\n")
            return "\(workflow.name):\n\(steps)"
        }.joined(separator: "\n\n")

        var prompt = """
        Active Application Context:
        The frontmost app appears to be \(appName). \(tagline)

        App Interface Structure:
        \(systemPrompt)

        Key App Concepts:
        \(conceptText)
        """

        if !workflowText.isEmpty {
            prompt += """

        Standard Workflows:
        \(workflowText)
        """
        }

        prompt += """

        Use this domain knowledge to assist the user with \(appName) workflows naturally and accurately.
        """
        return prompt
    }

    #if os(macOS)
    static func contextForFrontmostApplication(excluding ownBundleIdentifier: String? = Bundle.main.bundleIdentifier) -> SuzzmeAppSkillContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != ownBundleIdentifier else { return nil }
        return context(bundleIdentifier: app.bundleIdentifier, appName: app.localizedName)
    }
    #else
    static func contextForFrontmostApplication(excluding ownBundleIdentifier: String? = nil) -> SuzzmeAppSkillContext? {
        nil
    }
    #endif

    static func context(bundleIdentifier: String?, appName: String?) -> SuzzmeAppSkillContext? {
        let normalizedBundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalizedBundleIdentifier,
           let exact = all.first(where: { $0.bundleIdentifier.lowercased() == normalizedBundleIdentifier }) {
            return exact
        }

        let normalizedAppName = appName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalizedAppName.isEmpty else { return nil }
        return all.first { context in
            let normalizedContextName = context.appName.lowercased()
            return normalizedAppName.contains(normalizedContextName)
                || normalizedContextName.contains(normalizedAppName)
                || aliases[context.bundleIdentifier, default: []].contains { normalizedAppName.contains($0) }
        }
    }

    private static let aliases: [String: [String]] = [
        "com.microsoft.VSCode": ["visual studio code", "code", "vscode"],
        "com.apple.FinalCut": ["final cut", "final cut pro"],
        "com.apple.dt.Xcode": ["xcode"],
        "com.adobe.AdobePremierePro": ["premiere", "premiere pro"],
        "org.blender.blender": ["blender"],
        "com.figma.Desktop": ["figma"],
        "com.microsoft.Excel": ["excel"],
        "notion.id": ["notion"],
        "com.apple.Terminal": ["terminal"],
        "com.apple.Notes": ["notes", "apple notes"],
        "com.apple.reminders": ["reminders", "apple reminders"],
        "com.spotify.client": ["spotify"],
        "com.linear": ["linear"],
        "com.airtable.desktop": ["airtable"],
        "com.tinyspeck.slackmacgap": ["slack"]
    ]

    static let all: [SuzzmeAppSkillContext] = [
        SuzzmeAppSkillContext(
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            tagline: "Apple's IDE for developing iOS, macOS, watchOS, and visionOS apps with Swift and SwiftUI.",
            systemPrompt: "Xcode areas: Navigator (Cmd+1-8 for Project, Source Control, Search, Issues), Editor (center), Inspector (Cmd+Option+1-7), Debug Area (Cmd+Shift+Y). Canvas / SwiftUI Previews (Cmd+Option+Enter). Shortcuts: Cmd+B build, Cmd+R run, Cmd+. stop, Cmd+Shift+K clean, Cmd+/ comment.",
            concepts: [
                "Navigator tabs — Project (1), Source Control (2), Search (4), Issues (5), Debug (7), Breakpoints (8)",
                "SwiftUI Canvas — real-time preview beside code, toggle with Cmd+Option+Enter",
                "Inspector panel — inspect attributes, identity, and accessibility on the right side",
                "Asset Catalog — manages AppIcon, image sets, colors, and vector PDF/SVG marks",
                "SPM Dependencies — Swift Package Manager packages integrated directly into project"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Build and run scheme",
                    steps: [
                        "Select destination in toolbar scheme picker",
                        "Press Cmd+B to build and verify no compiler errors",
                        "Press Cmd+R to launch in simulator or on device",
                        "Check debug console with Cmd+Shift+Y if issues occur"
                    ]
                )
            ]
        ),
        SuzzmeAppSkillContext(
            appName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            tagline: "Extensible code editor with support for modern web, Python, TypeScript, and cloud development.",
            systemPrompt: "VS Code areas: Activity Bar (left), Side Bar (Cmd+B to toggle), Editor Groups (center), Panel (Cmd+J for Terminal/Output/Problems), Status Bar (bottom). Command Palette (Cmd+Shift+P) executes all commands. Quick Open (Cmd+P) finds files.",
            concepts: [
                "Command Palette — Cmd+Shift+P for any action or setting",
                "Quick Open — Cmd+P to jump to any file by name",
                "Integrated Terminal — Ctrl+` or Cmd+J to toggle",
                "Extensions — install language servers, formatters, and AI companions",
                "Multi-root Workspaces — configure project settings in .vscode/settings.json"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Find and replace across project",
                    steps: [
                        "Press Cmd+Shift+F to open global search",
                        "Enter search query and replacement text",
                        "Review matches in sidebar",
                        "Click Replace All or use Cmd+Option+Enter"
                    ]
                )
            ]
        ),
        SuzzmeAppSkillContext(
            appName: "Notion",
            bundleIdentifier: "notion.id",
            tagline: "All-in-one workspace for notes, docs, wikis, and relational databases.",
            systemPrompt: "Notion interface: Sidebar (left with pages, favorites, workspace), Page Canvas (center), Top Bar (share, updates, favorite, page options). Slash commands (/) insert any block type. Databases provide Table, Board, Calendar, Timeline, List, and Gallery views.",
            concepts: [
                "Blocks — everything is a block (paragraph, heading, callout, table, image)",
                "Slash commands — type / to insert any block or formatting",
                "Databases — structured tables with properties: text, select, status, date, person, formula, relation",
                "Linked views — embed a database view into any other document",
                "Internal Integrations — connect API tokens with specific page access"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Create a structured database",
                    steps: [
                        "Type /database and choose Inline Database",
                        "Add properties (Status, Due Date, Assignee)",
                        "Create views (Board for kanban, Calendar for deadlines)",
                        "Connect to Suzzme for instant querying"
                    ]
                )
            ]
        ),
        SuzzmeAppSkillContext(
            appName: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            tagline: "Collaborative interface design tool for UX/UI, wireframes, and design systems.",
            systemPrompt: "Figma interface: Left sidebar (Layers, Assets, Pages), Center (Infinite Canvas), Right sidebar (Design, Prototype, Inspect), Top toolbar (Tools, Frame, Shape, Pen, Text, Component, Plugins). Shortcuts: V Move, F Frame, R Rectangle, T Text, Option+drag Duplicate, Cmd+G Group, Shift+A Auto Layout.",
            concepts: [
                "Auto Layout — Shift+A creates responsive flexbox-like containers with gap and padding",
                "Components & Variants — Cmd+Option+K creates reusable components; configure properties in right panel",
                "Design tokens — color styles, typography styles, and effect styles",
                "Dev Mode — toggle Shift+D to inspect CSS, Swift, or Android code",
                "Vector networks — precise bezier paths"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Build a responsive card component",
                    steps: [
                        "Group content elements and press Shift+A for Auto Layout",
                        "Set direction (vertical/horizontal), padding, and item spacing",
                        "Set width to Fill container for responsiveness",
                        "Press Cmd+Option+K to turn into a master component"
                    ]
                )
            ]
        ),
        SuzzmeAppSkillContext(
            appName: "Linear",
            bundleIdentifier: "com.linear",
            tagline: "Fast, issue-tracking and product management system built for high-performance software teams.",
            systemPrompt: "Linear interface: Sidebar (Workspace, Teams, My Issues, Cycles, Projects, Roadmap), Main View (List or Board view with filters and grouping), Right Detail Pane (Issue properties, relations, activity, comments). Shortcuts: C new issue, Cmd+K command bar, / filter, Space preview.",
            concepts: [
                "Cycles — automated sprints (e.g. 2-week iterations) that roll over uncompleted work",
                "Projects & Milestones — high-level initiatives grouping multiple issues",
                "Triage inbox — incoming issues waiting for acceptance and team routing",
                "Identifiers — ENG-123 or DES-456 used in Git branches and commits",
                "API Keys — personal tokens created in Security & Access settings"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Quick create and triage issue",
                    steps: [
                        "Press C from anywhere in Linear to open issue creator",
                        "Add title, description, team, assignee, and priority",
                        "Set cycle or project if applicable",
                        "Press Cmd+Enter to submit"
                    ]
                )
            ]
        ),
        SuzzmeAppSkillContext(
            appName: "Airtable",
            bundleIdentifier: "com.airtable.desktop",
            tagline: "Low-code platform for building relational database applications and workflows.",
            systemPrompt: "Airtable interface: Base Navigator (top), Views sidebar (left with Grid, Kanban, Gallery, Form, Calendar, Timeline), Data Grid (center), Extensions/Automations (top right). Records have fields with rich types (Single line, Linked records, Formulas, Lookups, Rollups, Attachments).",
            concepts: [
                "Bases & Tables — bases contain multiple related tables",
                "Linked Records — establish foreign key relationships between tables",
                "Rollup & Lookup — aggregate or pull fields across linked records",
                "Personal Access Tokens — PATs scoped per-base with data.records:read/write permissions",
                "Automations — trigger actions based on record creation or field changes"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Set up API token for Suzzme integration",
                    steps: [
                        "Open airtable.com/create/tokens",
                        "Name the token (e.g. 'Suzzme Personal Companion')",
                        "Add scopes: data.records:read, schema.bases:read",
                        "Select the target base under Access",
                        "Paste token into Suzzme Knowledge Sources"
                    ]
                )
            ]
        ),
        SuzzmeAppSkillContext(
            appName: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            tagline: "macOS command-line interface for shell operations, scripting, and system administration.",
            systemPrompt: "Terminal shell interface (default zsh). Cmd+N new window, Cmd+T new tab, Cmd+K clear scrollback. Ctrl+C interrupt, Ctrl+R reverse search, Tab autocomplete. Homebrew (`brew`) is the primary package manager.",
            concepts: [
                "Shell commands — command [-flags] [arguments]",
                "Piping & Redirection — | pipes stdout to stdin, > writes to file, >> appends",
                "Homebrew — brew install <package> to install CLI tools",
                "Environment Variables — export VAR=val stored in ~/.zshrc",
                "Process Management — ps, kill, top, htop"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Inspect git repo status",
                    steps: [
                        "Run git status to view changed and untracked files",
                        "Run git log --oneline -n 5 to view recent commits",
                        "Run git diff to inspect uncommitted changes"
                    ]
                )
            ]
        ),
        SuzzmeAppSkillContext(
            appName: "Apple Notes",
            bundleIdentifier: "com.apple.Notes",
            tagline: "Apple's native note-taking app syncing across Mac, iPhone, and iPad via iCloud.",
            systemPrompt: "Apple Notes: Folders/Accounts sidebar (left), Note list (middle), Note editor (right). Supports rich text, checklists, tables, attachments, scans, and Quick Notes (Fn+Q).",
            concepts: [
                "Folders & Smart Folders — organize notes manually or with tags (#tag)",
                "Quick Note — Fn+Q or bottom-right hot corner opens an instant note",
                "Checklists — Cmd+Shift+L toggles interactive checklist items",
                "iCloud Sync — changes sync in real-time across iOS and macOS",
                "AppleScript / Scripting Bridge — enables native programmatic access"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Create and tag a note",
                    steps: [
                        "Press Cmd+N to create a new note",
                        "Type title on first line",
                        "Add #project or #todo tag anywhere in text",
                        "Notes automatically indexes into smart folders"
                    ]
                )
            ]
        ),
        SuzzmeAppSkillContext(
            appName: "Apple Reminders",
            bundleIdentifier: "com.apple.reminders",
            tagline: "Apple's native task and reminder manager with iCloud sync and Siri integration.",
            systemPrompt: "Reminders interface: Smart lists (Today, Scheduled, All, Flagged, Completed) on top, custom lists on bottom, tasks in center. Supports due dates, times, priorities, subtasks, tags, and location alerts.",
            concepts: [
                "Smart Lists — Today, Scheduled, Flagged, All",
                "EventKit Framework — native macOS API providing fast, private local access",
                "Natural Language Dates — typing 'tomorrow at 3pm' automatically schedules the reminder",
                "Subtasks & Checklists — indent tasks or add checklist sections",
                "Siri & iOS Sync — instant synchronization across all user devices"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Add task with due date",
                    steps: [
                        "Press Cmd+N to create a reminder",
                        "Type task name and date/time",
                        "Press Return to save",
                        "Suzzme Daily Summary automatically surfaces scheduled reminders"
                    ]
                )
            ]
        ),
        SuzzmeAppSkillContext(
            appName: "Spotify",
            bundleIdentifier: "com.spotify.client",
            tagline: "Music streaming service with playlist management and playback control.",
            systemPrompt: "Spotify interface: Left sidebar (Your Library, Playlists, Liked Songs), Center (Main content, Browse, Search, Album/Playlist view), Bottom bar (Now Playing, scrubber, volume, devices, shuffle/repeat).",
            concepts: [
                "Now Playing — track, artist, album, duration, playback state",
                "AppleScript Control — `osascript -e 'tell application \"Spotify\" to play/pause/next track'`",
                "Spotify Connect — transfer playback seamlessly between Mac, iPhone, and speakers",
                "Playlists & Queue — add tracks to current playback queue or custom lists"
            ],
            workflows: [
                SuzzmeAppSkillWorkflow(
                    name: "Control playback via AppleScript",
                    steps: [
                        "Play/Pause: tell application \"Spotify\" to playpause",
                        "Next Track: tell application \"Spotify\" to next track",
                        "Get Current Track: tell application \"Spotify\" to get name of current track"
                    ]
                )
            ]
        )
    ]
}

