# Suzzme

<p align="center">
  <img src="dynamic-island-lab/assets/mascot.png" alt="Suzzme Mascot" width="130" style="border-radius: 26px;" />
</p>

<p align="center">
  <strong>Your daily morning briefing on Mac and iPhone — powered by on-device AI.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg?style=flat-square&logo=swift" alt="Swift 6.0" />
  <img src="https://img.shields.io/badge/Platforms-macOS%2014%2B%20%7C%20iOS%2017%2B-blue.svg?style=flat-square&logo=apple" alt="macOS 14+ | iOS 17+" />
  <img src="https://img.shields.io/badge/Privacy-On--Device%20First-green.svg?style=flat-square" alt="Privacy-First" />
  <img src="https://img.shields.io/badge/AI-Apple%20Foundation%20Models-black.svg?style=flat-square" alt="Apple Foundation Models" />
</p>

---

## ☀️ What is Suzzme?

**Suzzme** is a personal assistant app for **macOS and iOS** that connects to your everyday tools (Calendar, Reminders, WhatsApp, Gmail, Slack, Notion) and **summarizes your entire day at a specific time you choose**.

### The Morning Routine

Suppose you schedule your daily briefing for **8:00 AM**. At 8:00 AM sharp, Suzzme greets you:

> *"Hey Rehan, how are you doing? Here are your important updates for today..."*
>
> 🗓️ **3 meetings today** — First one starts at 10:30 AM with the design team.  
> ✉️ **2 urgent emails** — Project sign-off request from Sarah.  
> 💬 **WhatsApp updates** — Family group lunch plans confirmed for 1:00 PM.  
> ✅ **Tasks due** — Review pull request #14 before 5:00 PM.

---

## 🔄 How It Works: Mac & iPhone in Sync

Suzzme uses a smart, battery-friendly approach across your Apple devices:

1. **Mac prepares the summary**: Your Mac connects to your permitted sources (Calendar, Reminders, WhatsApp chats, Gmail, Slack, Notion) and uses on-device AI (Apple's Foundation Models) to create your daily briefing.
2. **iPhone syncs automatically**: Sign in with the same Google account on your Mac and iPhone. Suzzme securely shares the prepared summary with your iPhone companion.
3. **Zero battery drain**: Your iPhone doesn't need to burn battery scanning apps or running heavy AI models in the background. It simply presents your prepared briefing the moment you pick up your phone, complete with Lock Screen widgets and Live Activities.

---

## 📸 App Screenshots

### macOS Experience
| Home & Daily Briefing | Sidebar & Liquid Glass UI |
| :---: | :---: |
| <img src="docs/Previews/home-summarize-day-composer-mac.png" alt="macOS Home" width="460" /> | <img src="docs/Previews/sidebar-mascot-glass-mac.png" alt="Sidebar & Interface" width="460" /> |

<p align="center">
  <em>Suzzme rests right under the MacBook display notch when you need it:</em><br/>
  <img src="docs/Previews/mac-notch-listening.png" alt="MacBook Notch Presence" width="380" />
</p>

### iOS Companion Experience
| iPhone Companion Screen | Today & Schedule Overview |
| :---: | :---: |
| <img src="docs/Previews/iphone-companion-current.png" alt="iOS Companion" width="340" /> | <img src="docs/Previews/iphone-today-guest.png" alt="iOS Today Schedule" width="340" /> |

---

## ✨ Key Features

* ⏰ **Scheduled Daily Briefings**: Set your preferred time (morning or evening) to get a calm, accurate summary of your schedule, tasks, and messages.
* 🗣️ **Ask Suzzme (Voice & Text)**: Chat naturally with Suzzme. Ask questions about your upcoming meetings, tasks, or notes using voice or keyboard.
* 💻 **Mac Notch Companion**: Snaps right under the MacBook screen notch, with quick global shortcuts and menu bar access.
* 📱 **iPhone Dynamic Island & Widgets**: Track voice conversations and summary updates directly on your Lock Screen and Dynamic Island.
* 🔒 **100% Privacy-First**:
  * Runs on-device AI — your private data stays on your hardware.
  * No continuous background tracking or audio recording.
  * Never invents or hallucinates facts.
  * Actions (like creating an event or reminder) always ask for your confirmation first.

---

## 🛠️ Sources & Integrations

Suzzme only accesses what you explicitly allow:

| Source | What Suzzme Reads |
| :--- | :--- |
| **Apple Calendar & Reminders** | Today's events, deadlines, and scheduled tasks |
| **Contacts** | Names and relationships for personalized context |
| **WhatsApp (macOS)** | Only chats you choose from your local WhatsApp folder |
| **Gmail** | Sender, subject, and date of recent emails (no email bodies without permission) |
| **Slack, Notion & GitHub** | Read-only updates via the built-in MCP connector server |

---

## 🚀 Getting Started

### Requirements
* **Mac**: macOS 14.0 (Sonoma) or macOS 15+ (Sequoia)
* **iPhone**: iOS 17.0 or later
* **Xcode**: Version 16.0 or later

### Quick Setup

1. **Clone the repository**:
   ```sh
   git clone https://github.com/Rehan0707/Suzzme.git
   cd Suzzme
   ```

2. **Open in Xcode**:
   ```sh
   open Suzzme/Suzzme.xcodeproj
   ```

3. **Build & Run**:
   * Select the **Suzzme** scheme.
   * Choose **My Mac** or an **iOS Simulator** (e.g. iPhone 16 Pro).
   * Press `Cmd + R` to run!

---

## 📂 Project Structure

* [`Suzzme/`](Suzzme/) — The main Mac and iOS app codebase written in Swift 6.
* [`Suzzme/PresenceShared/`](Suzzme/PresenceShared/) — Shared models for Live Activities and widgets.
* [`Suzzme/SuzzmePresenceWidget/`](Suzzme/SuzzmePresenceWidget/) — iOS Dynamic Island and Lock Screen widget extension.
* [`Suzzme/ConnectorServer/`](Suzzme/ConnectorServer/) — MCP server connecting Slack, Notion, and GitHub.
* [`Suzzme/BrowserExtension/`](Suzzme/BrowserExtension/) — Chrome extension bridge for web context.
* [`voice-gateway/`](voice-gateway/) — Cloudflare Worker proxy for speech synthesis and transcription.
* [`dynamic-island-lab/`](dynamic-island-lab/) — Interactive browser prototype for Dynamic Island animations.
* [`docs/`](docs/) — Architecture guides, design documentation, and technical deep-dives.

---

## 📖 Learn More

* [Product Vision & Philosophy](Suzzme/PRODUCT_VISION.md)
* [Technical App Architecture](Suzzme/README.md)
* [Testing & Validation Guide](Suzzme/Validation/README.md)
* [Security & Network Design](Suzzme/WATCHED_LINKS_SECURITY.md)

---

## 📄 License

Proprietary © 2026 Rehan Sanadi and contributors.
