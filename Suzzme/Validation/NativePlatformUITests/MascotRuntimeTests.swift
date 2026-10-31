import XCTest

/// Uses a separately identified installation of the unmodified production app.
/// Typed requests exercise real state without asking for microphone permission.
final class MascotRuntimeTests: XCTestCase {
    @MainActor func testCloudHomeAndActualTypedRequest() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedWelcome", "YES", "-suzzme.appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["suzzme-home-talk"].waitForExistence(timeout: 60), app.debugDescription)
        let mascot = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Suzzme companion")).firstMatch
        XCTAssertTrue(mascot.exists, "Home must expose the meaningful companion to accessibility")
        XCTAssertEqual(mascot.value as? String, "Suzzme ready")
        capture(app, name: "mascot-home-light")
        let input = app.textFields["Your question"].exists ? app.textFields["Your question"] : app.textViews["Your question"]
        activate(input)
        input.typeText("What can you do?")
        activate(app.buttons["Send question"])
        XCTAssertTrue(app.staticTexts["Answered without generative AI"].waitForExistence(timeout: 45), app.debugDescription)
        capture(app, name: "mascot-actual-response")
        XCTAssertFalse(app.alerts.firstMatch.exists, "A typed request must not prompt for microphone access")
        app.terminate()
        app.launchArguments = ["-hasCompletedWelcome", "YES", "-suzzme.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["suzzme-home-talk"].waitForExistence(timeout: 60), app.debugDescription)
        capture(app, name: "mascot-home-dark-large-type")
    }

    @MainActor private func activate(_ element: XCUIElement) {
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        #if os(macOS)
        guard let window = app.windows.allElementsBoundByIndex.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            XCTFail("A main window is required")
            return
        }
        let attachment = XCTAttachment(screenshot: window.screenshot())
        #else
        let attachment = XCTAttachment(screenshot: app.screenshot())
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
