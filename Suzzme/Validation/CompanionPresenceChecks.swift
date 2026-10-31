import AppKit
import SwiftUI

/// Deterministic presentation policy checks. No panel, microphone or app UI is
/// opened, and simulated geometry is never evidence of physical-notch quality.
@main @MainActor struct CompanionPresenceChecks {
    static func main() {
        var passed = 0
        func check(_ value: Bool, _ label: String) {
            precondition(value, label)
            passed += 1
            print("PASS \(label)")
        }
        let quiet = MacAssistantSurfaceMetrics.size(state: .idle, signal: .none,
                                                     notchWidth: 480, review: nil, response: nil, notchHeight: 36)
        let hovered = MacAssistantSurfaceMetrics.size(state: .idle, signal: .none,
                                                       notchWidth: 480, review: nil, response: nil,
                                                       notchHeight: 36, isHovered: true)
        let active = MacAssistantSurfaceMetrics.size(state: .listening, signal: .none,
                                                      notchWidth: 480, review: nil, response: nil, notchHeight: 36)
        check(quiet.width >= 480 && active.width >= 480, "wide physical cutouts are never narrowed by a generic width cap")
        check(quiet.height - 36 <= 12 && hovered.height - 36 >= 44,
              "idle sits close to the cutout while hover reveals an accessible control")
        check(quiet.height < active.height, "listening expands the same attachment downward")
        let neck = SuzzmeNotchSurfaceShape(attached: true, neckWidth: 480)
            .path(in: CGRect(x: 0, y: 0, width: quiet.width, height: quiet.height))
        check(neck.contains(CGPoint(x: quiet.width / 2 - 238, y: 1))
              && neck.contains(CGPoint(x: quiet.width / 2 + 238, y: 1)), "the attachment covers both measured physical cutout edges")
        check(!neck.contains(CGPoint(x: 1, y: 1)), "concave outer top corners retain their clear silhouette")
        let screen = NSRect(x: -1_800, y: -300, width: 1_800, height: 1_000)
        let placement = MacAssistantPanelPlacement.frame(size: active, screenFrame: screen,
                                                         visibleFrame: screen, hasNotch: true, notchCenterX: -900)
        check(placement.maxY == screen.maxY && placement.midX == -900, "negative display origins retain the cutout center and top anchor")
        check(screen.contains(placement), "the active surface stays within its invocation display")
        let entry = NSRect(x: -990, y: screen.maxY - 32, width: 180, height: 32)
        check(MacPresencePointerRegion.contains(NSPoint(x: entry.midX, y: screen.maxY), in: entry),
              "a pointer pinned to the exact display top can reveal the physical notch")
        check(!MacPresencePointerRegion.contains(NSPoint(x: entry.midX, y: screen.maxY + 1), in: entry)
              && !MacPresencePointerRegion.contains(NSPoint(x: entry.minX - 1, y: entry.midY), in: entry),
              "notch entry cannot capture adjacent menu-bar or off-display space")
        check(!MacPresencePointerRegion.contains(.zero, in: .null)
              && !MacPresencePointerRegion.contains(.zero, in: .infinite)
              && !MacPresencePointerRegion.contains(NSPoint(x: CGFloat.nan, y: 0), in: entry),
              "invalid display and pointer geometry cannot reveal or intercept")
        let surfaceFrame = NSRect(x: -1_070, y: 560, width: 340, height: 140)
        let pointerShape = SuzzmeNotchSurfaceShape(attached: true, neckWidth: 180)
        check(MacPresencePointerRegion.contains(NSPoint(x: surfaceFrame.midX, y: surfaceFrame.maxY), in: surfaceFrame, shape: pointerShape),
              "the attached silhouette accepts a first click at the exact bezel edge")
        check(MacPresencePointerRegion.contains(NSPoint(x: surfaceFrame.midX, y: surfaceFrame.midY), in: surfaceFrame, shape: pointerShape),
              "the notch body keeps its native controls interactive")
        check(!MacPresencePointerRegion.contains(NSPoint(x: surfaceFrame.minX + 1, y: surfaceFrame.maxY - 1), in: surfaceFrame, shape: pointerShape)
              && !MacPresencePointerRegion.contains(NSPoint(x: surfaceFrame.maxX - 1, y: surfaceFrame.minY + 1), in: surfaceFrame, shape: pointerShape),
              "transparent concave and rounded corners pass clicks through")
        check(!MacPresencePointerRegion.contains(NSPoint(x: surfaceFrame.maxX + 1, y: surfaceFrame.midY), in: surfaceFrame, shape: pointerShape),
              "the edge bloom never enlarges the interactive silhouette")
        check(!MacPresencePointerRegion.contains(NSPoint(x: surfaceFrame.minX + 1, y: surfaceFrame.maxY - 1), in: surfaceFrame,
                                                shape: SuzzmeNotchSurfaceShape(attached: false, neckWidth: 0)),
              "non-notch rounded fallback corners also pass clicks through")
        var ownership = MacPresenceDisplayOwnership()
        let first = UUID(), second = UUID()
        check(ownership.resolve(interactionID: first, retainsInteraction: true, preferredID: 1, availableIDs: [1, 2]) == 1,
              "invocation captures its display")
        check(ownership.resolve(interactionID: first, retainsInteraction: true, preferredID: 2, availableIDs: [1, 2]) == 1,
              "cursor and audio updates cannot migrate an active interaction")
        check(ownership.resolve(interactionID: nil, retainsInteraction: true, preferredID: 2, availableIDs: [1, 2]) == 1,
              "the completed answer retains its display through reading")
        check(ownership.resolve(interactionID: second, retainsInteraction: true, preferredID: 2, availableIDs: [1, 2]) == 2,
              "a new request may select a new invocation display")
        check(ownership.resolve(interactionID: second, retainsInteraction: true, preferredID: 1, availableIDs: [1]) == 1,
              "disconnecting the owned display selects an available display")
        check(ownership.resolve(interactionID: nil, retainsInteraction: false, preferredID: 2, availableIDs: [1, 2]) == 2
              && ownership.displayID == nil, "ending the interaction releases display ownership")
        let phases: [SuzzmeAssistantState] = [.understanding, .listening, .transcribing, .gatheringContext, .reasoning, .planning, .awaitingConfirmation, .acting, .speaking, .success, .error]
        let projections = phases.map(SuzzmePresenceMotion.make(for:))
        check(projections.enumerated().allSatisfy { index, profile in
            projections.dropFirst(index + 1).allSatisfy { $0 != profile }
        }, "every semantic phase has a distinct finite visual interpretation")
        for state in SuzzmeAssistantState.allCases {
            let profile = SuzzmePresenceMotion.make(for: state)
            check(profile.duration.isFinite && profile.duration >= 0
                  && profile.entryDuration(for: .flow) + SuzzmeTheme.Motion.calm <= 1.1,
                  "\(state.rawValue) transition has a bounded completion interval")
            check(profile.entryDuration(for: .minimal) == 0
                  && !SuzzmePresenceMotion.allowsMotion(state: state, animation: .minimal, reduceMotion: false, isActive: true)
                  && !SuzzmePresenceMotion.allowsMotion(state: state, animation: .gentle, reduceMotion: true, isActive: true)
                  && !SuzzmePresenceMotion.allowsMotion(state: state, animation: .gentle, reduceMotion: false, isActive: false),
                  "\(state.rawValue) respects Minimal, Reduce Motion and inactive scenes")
        }
        check(!SuzzmePresenceMotion.allowsMotion(state: .idle, animation: .gentle, reduceMotion: false, isActive: true), "idle never schedules a motion cycle")
        check(MacAssistantPanelController.autoHideDelay(for: .awaitingConfirmation, signal: .none) == nil,
              "pending confirmation retains user agency without an automatic deadline")

        // Inspect the actual shared contour instead of rendering an unrelated
        // reference shape. Geometry checks do not establish hardware alignment.
        struct TraceElement: Equatable {
            let kind: Int
            let points: [CGPoint]
        }
        func trace(_ path: Path) -> [TraceElement] {
            var result: [TraceElement] = []
            path.forEach { element in
                switch element {
                case let .move(to: point): result.append(.init(kind: 0, points: [point]))
                case let .line(to: point): result.append(.init(kind: 1, points: [point]))
                case let .quadCurve(to: point, control: control):
                    result.append(.init(kind: 2, points: [control, point]))
                case let .curve(to: point, control1: first, control2: second):
                    result.append(.init(kind: 3, points: [first, second, point]))
                case .closeSubpath: result.append(.init(kind: 4, points: []))
                }
            }
            return result
        }
        func remainsInBounds(_ path: Path, _ rect: CGRect) -> Bool {
            let points = trace(path).flatMap(\.points)
            return !points.isEmpty && points.allSatisfy {
                $0.x.isFinite && $0.y.isFinite
                    && $0.x >= rect.minX && $0.x <= rect.maxX
                    && $0.y >= rect.minY && $0.y <= rect.maxY
            }
        }
        let contourRect = CGRect(x: -50, y: 12, width: 300, height: 120)
        var contour = SuzzmeNotchSurfaceShape(attached: true, neckWidth: 180,
                                             topCornerRadius: 8, bottomCornerRadius: 18)
        let silhouette = contour.path(in: contourRect)
        let skirt = contour.skirtPath(in: contourRect)
        let perimeter = trace(skirt)
        let bodyTop = contourRect.minY
        check(trace(silhouette).contains { $0.kind == 4 }, "the filled notch silhouette is closed")
        check(!perimeter.contains { $0.kind == 4 }, "the attached glowing skirt remains open")
        check(perimeter.filter { $0.kind == 2 }.count == 4,
              "the visible perimeter contains both concave shoulders and rounded bottom corners")
        check(perimeter.first?.points == [CGPoint(x: contourRect.minX, y: bodyTop)]
              && perimeter.last?.points.last == CGPoint(x: contourRect.maxX, y: bodyTop),
              "the skirt joins the display top at both outer corners")
        let shoulderCurves = perimeter.filter { $0.kind == 2 }
        check(shoulderCurves.first?.points == [CGPoint(x: contourRect.minX + 8, y: bodyTop),
                                              CGPoint(x: contourRect.minX + 8, y: bodyTop + 8)]
              && shoulderCurves.last?.points == [CGPoint(x: contourRect.maxX - 8, y: bodyTop),
                                                 CGPoint(x: contourRect.maxX, y: bodyTop)],
              "top corners curve concavely into the body rather than rounding inward from its sides")
        var previousPoint: CGPoint?
        var drawsBezelLine = false
        for element in perimeter {
            if element.kind == 1, let previousPoint, let point = element.points.last,
               previousPoint.y == bodyTop && point.y == bodyTop && previousPoint.x != point.x {
                drawsBezelLine = true
            }
            previousPoint = element.points.last ?? previousPoint
        }
        check(!drawsBezelLine, "the open glow never strokes the flat bezel line")
        check(remainsInBounds(silhouette, contourRect) && remainsInBounds(skirt, contourRect),
              "offset rectangle contours stay finite and within their own bounds")
        check(silhouette.contains(CGPoint(x: contourRect.midX - 88, y: contourRect.minY + 1))
              && silhouette.contains(CGPoint(x: contourRect.midX + 88, y: contourRect.minY + 1))
              && silhouette.contains(CGPoint(x: contourRect.minX + 9, y: contourRect.minY + 1))
              && silhouette.contains(CGPoint(x: contourRect.maxX - 9, y: contourRect.minY + 1))
              && !silhouette.contains(CGPoint(x: contourRect.minX + 1, y: contourRect.minY + 1)),
              "black upper wings connect the physical cutout to the expanded surface while outer concave corners remain clear")
        let upperBand = (0...32).map { index in
            CGPoint(x: contourRect.minX + 9 + CGFloat(index) * (contourRect.width - 18) / 32,
                    y: contourRect.minY + 9)
        }
        check(upperBand.allSatisfy { silhouette.contains($0) },
              "a continuous black band spans both expanded wings just below the concave corner radius")
        let shallowInset = MacAssistantSurfaceMetrics.size(state: .listening, signal: .none,
                                                           notchWidth: 180, review: nil, response: nil, notchHeight: 24)
        let deepInset = MacAssistantSurfaceMetrics.size(state: .listening, signal: .none,
                                                        notchWidth: 180, review: nil, response: nil, notchHeight: 48)
        let shallowSilhouette = contour.path(in: CGRect(origin: .zero, size: shallowInset))
        let deepSilhouette = contour.path(in: CGRect(origin: .zero, size: deepInset))
        let insetBand = (0...32).map { index in
            CGPoint(x: 9 + CGFloat(index) * (shallowInset.width - 18) / 32, y: 9)
        }
        check(shallowInset.width == deepInset.width && deepInset.height == shallowInset.height + 24
              && insetBand.allSatisfy { shallowSilhouette.contains($0) && deepSilhouette.contains($0) },
              "different physical content insets preserve the same gap-free display-top silhouette")
        contour.topCornerRadius = 10_000
        contour.bottomCornerRadius = 10_000
        check(remainsInBounds(contour.path(in: contourRect), contourRect)
              && remainsInBounds(contour.skirtPath(in: contourRect), contourRect),
              "oversized corner radii clamp without crossing the body bounds")
        contour.topCornerRadius = -8
        contour.bottomCornerRadius = -18
        check(remainsInBounds(contour.path(in: contourRect), contourRect)
              && remainsInBounds(contour.skirtPath(in: contourRect), contourRect),
              "negative corner radii produce safe finite contours")
        contour.topCornerRadius = .nan
        contour.bottomCornerRadius = .infinity
        let nonfiniteRadius = trace(contour.skirtPath(in: contourRect))
        contour.topCornerRadius = 0
        contour.bottomCornerRadius = 0
        check(nonfiniteRadius == trace(contour.skirtPath(in: contourRect)),
              "nonfinite corner radii use the safe zero-radius contour")
        let tinyRect = CGRect(x: 3, y: -9, width: 20, height: 1)
        let tinyContour = SuzzmeNotchSurfaceShape(attached: true, neckWidth: 18,
                                                 topCornerRadius: 80, bottomCornerRadius: 80)
        check(remainsInBounds(tinyContour.path(in: tinyRect), tinyRect)
              && remainsInBounds(tinyContour.skirtPath(in: tinyRect), tinyRect),
              "a nearly collapsed surface retains finite geometry")
        let invalidRects: [CGRect] = [.zero, .null, .infinite,
                                      CGRect(x: 0, y: 0, width: -1, height: 10),
                                      CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)]
        for rect in invalidRects where !contour.path(in: rect).isEmpty || !contour.skirtPath(in: rect).isEmpty {
            print("Invalid rectangle unexpectedly produced a contour: \(rect)")
            fflush(nil)
        }
        check(invalidRects.allSatisfy { contour.path(in: $0).isEmpty && contour.skirtPath(in: $0).isEmpty },
              "empty and invalid rectangles cannot emit invalid drawing coordinates")
        contour.animatableData = .init(6, 14)
        let initialContour = trace(contour.skirtPath(in: contourRect))
        contour.animatableData = .init(12, 22)
        let expandedContour = trace(contour.skirtPath(in: contourRect))
        contour.animatableData = .init(9, 18)
        let intermediateContour = trace(contour.skirtPath(in: contourRect))
        check(contour.topCornerRadius == 9 && contour.bottomCornerRadius == 18,
              "animation updates both corner radii on the actual shape")
        check(initialContour != expandedContour && intermediateContour != initialContour
              && intermediateContour != expandedContour,
              "intermediate radius values morph the same contour instead of swapping shapes")
        let fallbackContour = SuzzmeNotchSurfaceShape(attached: false, neckWidth: 180,
                                                     topCornerRadius: 8, bottomCornerRadius: 18)
        let fallbackFill = fallbackContour.path(in: contourRect)
        let fallbackSkirt = fallbackContour.skirtPath(in: contourRect)
        check(trace(fallbackFill) == trace(fallbackSkirt)
              && trace(fallbackFill) == trace(RoundedRectangle(cornerRadius: 24, style: .continuous).path(in: contourRect)),
              "non-notch screens keep a matching continuous rounded fallback surface and rim")
        print("Companion Presence checks: \(passed) passed / 0 failed")
    }
}
