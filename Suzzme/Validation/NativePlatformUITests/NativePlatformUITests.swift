import XCTest

/// Runs the real @main, persistence, environment, routes and intelligence.
/// The driver changes only the test installation's bundle ID, never its services.
final class NativePlatformUITests: XCTestCase {
    @MainActor private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }
    @MainActor private func launch(welcome: Bool, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedWelcome", welcome ? "YES" : "NO", "-suzzme.appearance", appearance]
        app.launch()
        return app
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        #if os(macOS)
        let windows = app.windows.allElementsBoundByIndex
        guard let window = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            XCTFail("The production app has no window to capture")
            return
        }
        // The app can own both a workspace and a notch panel. Capture its
        // workspace bounds rather than a union containing the user's desktop.
        let attachment = XCTAttachment(screenshot: window.screenshot())
        #else
        let attachment = XCTAttachment(screenshot: app.screenshot())
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func test01ProductionFirstRunAndOnboarding() {
        let app = launch(welcome: false)
        XCTAssertTrue(app.buttons["suzzme-continue-local"].waitForExistence(timeout: 60), app.debugDescription)
        capture(app, "01-welcome-light")
        #if os(iOS)
        XCTAssertTrue(app.buttons["suzzme-sign-in-apple"].exists)
        #endif
        XCTAssertTrue(app.buttons["suzzme-sign-in-google"].exists)
        activate(app.buttons["suzzme-sign-in-email"])
        XCTAssertTrue(app.textFields["suzzme-email-address"].waitForExistence(timeout: 10))
        activate(app.buttons["Close"])
        activate(app.buttons["suzzme-continue-local"])
        XCTAssertTrue(app.staticTexts["Make it personal"].waitForExistence(timeout: 10))
        for index in 0..<8 {
            capture(app, "02-onboarding-\(index)")
            let finish = app.buttons["Start using Suzzme"]
            if finish.exists { activate(finish); break }
            let next = app.buttons["Continue"]
            XCTAssertTrue(next.exists, app.debugDescription)
            activate(next)
        }
        XCTAssertTrue(app.buttons["suzzme-home-talk"].waitForExistence(timeout: 20), app.debugDescription)
        capture(app, "03-production-home-light")
        XCTAssertTrue(app.textFields["Your question"].exists || app.textViews["Your question"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Launch must not ask for optional permissions")
    }

    @MainActor func test02RealTextConversationAndFollowUp() {
        let app = launch(welcome: true)
        XCTAssertTrue(app.buttons["suzzme-home-talk"].waitForExistence(timeout: 60), app.debugDescription)
        let homeInput = app.textFields["Your question"].exists ? app.textFields["Your question"] : app.textViews["Your question"]
        activate(homeInput)
        homeInput.typeText("What can you do?")
        activate(app.buttons["Send question"])
        let attribution = app.staticTexts["Answered without generative AI"]
        XCTAssertTrue(attribution.waitForExistence(timeout: 45), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "I can help you understand your day")).firstMatch.exists)
        capture(app, "04-real-core-conversation")
        let input = app.textFields["suzzme-assistant-input"].exists ? app.textFields["suzzme-assistant-input"] : app.textViews["suzzme-assistant-input"]
        XCTAssertTrue(input.exists, app.debugDescription)
        activate(input)
        input.typeText("Explain photosynthesis")
        activate(app.buttons["suzzme-assistant-submit"])
        let explanation = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "On-device answers are unavailable"))
        let generated = app.staticTexts["Generated on this device"]
        // Either real capability is legitimate. The test never injects an answer.
        let ready = NSPredicate { _, _ in explanation.firstMatch.exists || generated.exists }
        expectation(for: ready, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "I can help you understand your day")).firstMatch.exists,
                      "A follow-up must retain the first real answer")
        capture(app, "05-follow-up-and-real-availability")
        activate(app.buttons["Done"].firstMatch)
        XCTAssertTrue(app.buttons["suzzme-home-talk"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Typed conversation must not request microphone permission")
    }

    @MainActor func test03NativeRoutesAndDarkAppearance() {
        let app = launch(welcome: true, appearance: "dark")
        XCTAssertTrue(app.buttons["suzzme-home-talk"].waitForExistence(timeout: 60), app.debugDescription)
        capture(app, "06-production-home-dark")
        #if os(iOS)
        for route in ["Today", "Daily Summary", "Personal Memory", "Sources", "History"] {
            activate(app.buttons["Navigate Suzzme"])
            activate(app.buttons[route].firstMatch)
            XCTAssertTrue(app.navigationBars[route].waitForExistence(timeout: 10), app.debugDescription)
            capture(app, "07-route-\(route)")
            activate(app.navigationBars.buttons.firstMatch)
        }
        activate(app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        capture(app, "08-settings-dark")
        #else
        for route in ["today", "briefing", "memory", "sources", "history", "settings", "home"] {
            let row = app.descendants(matching: .any)["suzzme-navigation-\(route)"].firstMatch
            XCTAssertTrue(row.exists, app.debugDescription)
            activate(row)
            capture(app, "07-route-\(route)")
        }
        #endif
    }

    #if os(iOS)
    @MainActor func test04VoiceSettingsAndColoredIntegrations() {
        for appearance in ["light", "dark"] {
            let app = launch(welcome: true, appearance: appearance)
            XCTAssertTrue(app.buttons["suzzme-home-talk"].waitForExistence(timeout: 60), app.debugDescription)
            activate(app.buttons["Settings"])
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
            let voice = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Voice")).firstMatch
            XCTAssertTrue(voice.exists, app.debugDescription)
            activate(voice)
            XCTAssertTrue(app.navigationBars["Voice"].waitForExistence(timeout: 10), app.debugDescription)
            capture(app, "09-voice-settings-\(appearance)")
            activate(app.navigationBars.buttons.firstMatch)
            let integrations = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Integrations")).firstMatch
            if !integrations.isHittable { app.scrollViews.firstMatch.swipeUp() }
            XCTAssertTrue(integrations.exists, app.debugDescription)
            activate(integrations)
            XCTAssertTrue(app.navigationBars["Integrations"].waitForExistence(timeout: 10), app.debugDescription)
            capture(app, "10-colored-integrations-\(appearance)")
        }
    }

    @MainActor func test05SecondarySettingsRemainReachable() {
        let app = launch(welcome: true, appearance: "dark")
        XCTAssertTrue(app.buttons["suzzme-home-talk"].waitForExistence(timeout: 60), app.debugDescription)
        activate(app.buttons["Settings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        let routes = [
            ("Presence", "Suzzme Presence"),
            ("Talk to Suzzme", "Talk to Suzzme"),
            ("Daily Summary", "Daily Summary & Suggestions"),
            ("Privacy", "Privacy"),
            ("Notifications", "Notifications"),
            ("Accessibility", "Accessibility"),
            ("Profile", "Profile"),
            ("About Suzzme", "About Suzzme"),
            ("Suzzme Brain Lab", "Brain Lab")
        ]
        for (label, title) in routes {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            for _ in 0..<8 {
                if row.exists && row.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(row.exists && row.isHittable, "Settings route must be reachable: \(label)\n\(app.debugDescription)")
            activate(row)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), app.debugDescription)
            capture(app, "11-settings-detail-\(label)")
            XCTAssertFalse(app.alerts.firstMatch.exists, "Opening settings must not request optional permissions")
            activate(app.navigationBars.buttons.firstMatch)
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        }
    }

    @MainActor func test06SharedURLsFailClosedAndLinkedInScopeIsVisible() {
        let app = launch(welcome: true)
        XCTAssertTrue(app.buttons["suzzme-home-talk"].waitForExistence(timeout: 60), app.debugDescription)
        activate(app.buttons["Navigate Suzzme"])
        activate(app.buttons["Sources"].firstMatch)
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 10))
        let shared = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Shared webpages")).firstMatch
        for _ in 0..<8 {
            if shared.exists && shared.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(shared.exists && shared.isHittable, app.debugDescription)
        activate(shared)
        XCTAssertTrue(app.navigationBars["Shared webpages"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sharing unavailable"].exists,
                      "An unsigned acceptance build without a provisioned App Group must fail closed")
        capture(app, "12-shared-pages-unconfigured")
        activate(app.navigationBars.buttons.firstMatch)
        let integrations = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Integrations")).firstMatch
        for _ in 0..<8 {
            if integrations.exists && integrations.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(integrations.exists && integrations.isHittable, app.debugDescription)
        activate(integrations)
        XCTAssertTrue(app.navigationBars["Integrations"].waitForExistence(timeout: 10))
        let search = app.textFields["suzzme-integration-search"]
        activate(search)
        search.typeText("LinkedIn")
        let linkedIn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "LinkedIn")).firstMatch
        XCTAssertTrue(linkedIn.waitForExistence(timeout: 10), app.debugDescription)
        activate(linkedIn)
        XCTAssertTrue(app.navigationBars["LinkedIn"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Share selected text or a screenshot for local understanding. LinkedIn account, profile, feed and inbox retrieval are unavailable."].exists)
        capture(app, "13-linkedin-shared-content-only")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Reviewing scope must not request optional permissions")
    }
    #endif
}
