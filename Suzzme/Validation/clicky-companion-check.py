#!/usr/bin/env python3
"""Run shipping Clicky-derived panel owners with environment/view doubles.

NSStatusItem, NSPanel, event monitors, geometry and preference storage are real.
No voice, model, screen capture or external account is exercised by this harness.
"""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
menu=(root/'Suzzme/Platform/macOS/MacCompanionMenuController.swift').read_text()
menu=menu[:menu.index('/// Supplies scene actions')].removeprefix('#if os(macOS)\n')
cursor=(root/'Suzzme/Platform/macOS/MacCursorCompanion.swift').read_text()
cursor=cursor[:cursor.index('private struct MacCursorResponseView')].removeprefix('#if os(macOS)\n')
doubles='''
import AppKit
import SwiftUI
import Observation
@MainActor @Observable final class MacGlobalInvocationController {
 func refreshInputMonitoringPermission() {}
}
enum AppDestination { case home }
@MainActor @Observable final class AppEnvironment {
 let invocation: InvocationCoordinator
 init(defaults: UserDefaults) { invocation = InvocationCoordinator(defaults:defaults) }
 var currentInteractionID: UUID?
 var screenConsentRequestID: UUID?
 var presentedAction: String?
 var presenceState: SuzzmeAssistantState = .idle
 var presentedResponse: String?
}
@MainActor final class MacGuidanceOverlay {
 struct Presentation: Equatable {
  let reference: SpatialReference
  let context: ScreenContextMetadata
  let target: CGPoint
  let visibleFrame: CGRect
 }
 enum EndReason { case completed, invalidated }
 var presentation: Presentation?
 func isCurrent(_ presentation: Presentation) -> Bool { false }
 func isReturnCurrent(_ presentation: Presentation) -> Bool { false }
 func finishReturn(_ presentation: Presentation) {}
 func dismiss() {}
 func setCompanionPresent(_ present: Bool) {}
}
struct SuzzmeFace: View {
 let state: SuzzmeAssistantState; let color: Color; let lineWidth: CGFloat
 let animation: SuzzmePresenceAnimation
 var body: some View { Text("Suzzme") }
}
struct MacMenuBarView: View {
 let onClose: () -> Void; let onNavigate: (AppDestination) -> Void; let onSettings: () -> Void
 var body: some View { Text("Control-panel view double") }
}
struct MacCursorResponseView: View {
 var body: some View { Text("Cursor-content view double") }
}
'''
helpers='\nextension MacCompanionMenuController {\n var testedStatusItem: NSStatusItem? { statusItem }\n var testedPanel: NSPanel? { panel }\n var testedLocalMonitor: Any? { localMonitor }\n var testedGlobalMonitor: Any? { globalClickMonitor }\n func createTestPanel() { createPanel() }\n func installTestMonitors() { installDismissalMonitors() }\n func hideTestPanel() { hidePanel() }\n}\nextension MacCursorCompanion {\n var testedPanel: NSPanel? { panel }\n var testedLocalMonitor: Any? { localMouseMonitor }\n var testedGlobalMonitor: Any? { globalMouseMonitor }\n var testedDismissal: Task<Void,Never>? { dismissal }\n func createTestPanel() { createPanel() }\n}\n'
checks='''
@main @MainActor struct ClickyCompanionChecks {
 static func main() {
  _ = NSApplication.shared
  var count = 0
  func check(_ value: Bool, _ name: String) {
   count += 1
   if !value { print("FAIL: \\(name)"); exit(1) }
  }
  let displays = [CGRect(x:0,y:0,width:1440,height:900), CGRect(x:-1920,y:120,width:1920,height:1080),
                  CGRect(x:0,y:-900,width:1280,height:900), CGRect(x:0,y:0,width:240,height:320)]
  for display in displays {
   for x in [display.minX,display.midX,display.maxX] {
    let menuFrame=MacCompanionMenuController.frame(anchor:CGRect(x:x,y:display.maxY,width:24,height:24),visible:display)
    check(display.contains(menuFrame), "Menu panel stays on display")
    let cursorFrame=MacCursorCompanion.frame(pointer:CGPoint(x:x,y:display.minY),visible:display)
    check(display.contains(cursorFrame), "Cursor panel stays on display")
   }
  }
  let suite="dev.suzzme.clicky-conversion."+UUID().uuidString
  guard let defaults=UserDefaults(suiteName:suite) else { exit(1) }
  defer { defaults.removePersistentDomain(forName:suite) }
  let first=InvocationCoordinator(defaults:defaults)
  check(!first.cursorCompanionEnabled, "Cursor is opt-in")
  first.cursorCompanionEnabled=true
  check(InvocationCoordinator(defaults:defaults).cursorCompanionEnabled,"Cursor preference survives restart")
  first.cursorCompanionEnabled=false
  check(!InvocationCoordinator(defaults:defaults).cursorCompanionEnabled,"Cursor off survives restart")
  let environment=AppEnvironment(defaults:defaults)
  let controller=MacCompanionMenuController(environment:environment, invocation:MacGlobalInvocationController())
  check(controller.testedStatusItem != nil,"App-owned status item starts without a main-window scene bridge")
  controller.start(navigate:{ _ in },showSettings:{})
  let originalStatusItem=controller.testedStatusItem
  controller.start(navigate:{ _ in },showSettings:{})
  check(controller.testedStatusItem === originalStatusItem,"Starting twice reuses status item")
  controller.createTestPanel()
  guard let panel=controller.testedPanel else { exit(1) }
  check(panel.styleMask.contains(.nonactivatingPanel),"Menu does not activate other app")
  check(panel.canBecomeKey && !panel.canBecomeMain,"Typing works without becoming main window")
  check(panel.collectionBehavior.contains(.fullScreenAuxiliary),"Fullscreen auxiliary panel")
  check(!panel.isReleasedWhenClosed,"Single retained panel")
  controller.installTestMonitors()
  check(controller.testedLocalMonitor != nil,"Local dismissal monitor installed")
  controller.hideTestPanel()
  check(controller.testedLocalMonitor == nil && controller.testedGlobalMonitor == nil,"Hide removes monitors")
  controller.stop()
  check(controller.testedPanel == nil && controller.testedStatusItem == nil,"Stop removes panel and menu item")
  controller.stop()
  check(controller.testedPanel == nil,"Repeated stop is safe")
  let cursor=MacCursorCompanion(environment:environment,guidance:MacGuidanceOverlay())
  cursor.createTestPanel()
  check(cursor.testedPanel?.ignoresMouseEvents == true,"Cursor cannot click or execute")
  check(cursor.testedPanel?.canBecomeKey == false && cursor.testedPanel?.canBecomeMain == false,"Cursor cannot steal focus")
  check(cursor.testedPanel?.collectionBehavior.contains(.stationary) == true,"Cursor does not move Space")
  cursor.update()
  check(cursor.testedPanel?.isVisible == false,"Disabled cursor is hidden")
  environment.invocation.cursorCompanionEnabled=true
  environment.currentInteractionID=UUID(); environment.presenceState = .listening
  cursor.update()
  check(cursor.testedPanel?.isVisible == true,"Active owned request shows cursor")
  environment.screenConsentRequestID=UUID(); cursor.update()
  check(cursor.testedPanel?.isVisible == false,"Screen consent stays in interactive owner")
  environment.screenConsentRequestID=nil; environment.presentedAction="pending"; cursor.update()
  check(cursor.testedPanel?.isVisible == false,"Action confirmation stays in central owner")
  environment.presentedAction=nil; cursor.update()
  check(cursor.testedPanel?.isVisible == true,"Cleared review restores live request")
  environment.currentInteractionID=nil; cursor.update()
  check(cursor.testedPanel?.isVisible == false,"Retired request hides cursor")
  check(cursor.testedLocalMonitor == nil && cursor.testedGlobalMonitor == nil,"Retired request removes mouse monitors")
  cursor.dismiss(); cursor.dismiss()
  check(cursor.testedDismissal == nil,"Repeated dismissal clears timer")
  print("Clicky companion adapter checks: \\(count) passed / 0 failed")
 }
}
'''
with tempfile.TemporaryDirectory(prefix='SuzzmeClickyChecks-') as folder:
 output=Path(folder); source=output/'Checks.swift';source.write_text(doubles+menu+cursor+helpers+checks)
 cmd=['xcrun','swiftc','-swift-version','6','-parse-as-library','-disable-sandbox','-framework','AppKit','-framework','SwiftUI',
      '-module-cache-path',str(output/'ModuleCache')]
 for name in ['DesignSystem/Theme/SuzzmeTheme.swift','Core/Models/SuzzmeAssistantState.swift',
              'Core/Invocation/SuzzmePresenceTheme.swift','Core/Invocation/AssistantPresentation.swift',
              'Core/Models/SuzzmeItem.swift','Core/Context/SuzzmeContextItem.swift','Core/Context/SuzzmeContextQuery.swift',
              'Core/Privacy/PrivacyEngine.swift','Core/Context/ScreenContext.swift']:
  cmd.append(str(root/'Suzzme'/name))
 subprocess.run(cmd+[str(source),'-o',str(output/'Checks')],check=True)
 subprocess.run([str(output/'Checks')],check=True,timeout=30)
