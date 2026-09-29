import AppKit
import SwiftUI

struct Exploration: View {
    let compact: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                home(centered: true)
                home(centered: false)
            }
            .padding(24)
            HStack(alignment: .top, spacing: 28) {
                notch(connected: true)
                notch(connected: false)
            }.padding(24)
        }.frame(width: 900, height: 950).background(Color.white)
    }
    func home(centered: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: 24) {
            Text(centered ? "A · Face-led arrival" : "B · Editorial arrival").font(.caption).foregroundStyle(.secondary)
            Text("Good evening, Rehan.").font(.title3).foregroundStyle(.secondary)
            if centered {
                SuzzmeFace(color: .black, lineWidth: 5).frame(width: 112, height: 112)
                Text("Anything on your mind?").font(.title2.weight(.semibold))
            } else {
                HStack {
                    SuzzmeFace(color: .black, lineWidth: 4).frame(width: 64, height: 64)
                    Text("A little room\nto think.").font(.largeTitle.weight(.semibold))
                }
            }
            Button("Talk to Suzzme") {}.buttonStyle(.borderedProminent).controlSize(.large).tint(Color(red:0.44,green:0.29,blue:0.48))
            Button("Type instead") {}.buttonStyle(.plain).foregroundStyle(.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Today").font(.headline)
                Text("Project review").font(.title3.weight(.medium))
                Text("4:30 PM · Bring your design notes").foregroundStyle(.secondary)
                Divider().padding(.vertical,8)
                HStack { Text("Daily Summary"); Spacer(); Image(systemName:"arrow.right") }
                Text("Ready when you are").foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
        }.padding(28).frame(width:400,height:580).background(Color(white:0.98),in:RoundedRectangle(cornerRadius:24))
    }
    func notch(connected:Bool)->some View {
        VStack(spacing:connected ? 0 : 14) {
            RoundedRectangle(cornerRadius:8).fill(.black).frame(width:170,height:28)
            VStack(spacing:14) {
                SuzzmeFace(state:.listening,color:.white,lineWidth:3).frame(width:52,height:44)
                Text("Listening").font(.headline).foregroundStyle(.white)
                Text("Cancel").font(.caption).foregroundStyle(.white.opacity(0.7))
            }.padding(20).frame(width:connected ? 290 : 310)
             .background(.black,in:UnevenRoundedRectangle(topLeadingRadius:connected ? 0 : 24,bottomLeadingRadius:26,bottomTrailingRadius:26,topTrailingRadius:connected ? 0 : 24))
             .overlay(alignment:.bottom) { Capsule().fill(Color.purple.opacity(0.5)).frame(width:130,height:2).blur(radius:2) }
            Text(connected ? "A · Connected, grows downward" : "B · Detached floating panel").font(.caption).padding(.top,12)
        }.frame(width:400,height:270,alignment:.top)
    }
}

@main @MainActor struct RenderExploration {
 static func main() {
    _ = NSApplication.shared
    let view=NSHostingView(rootView:Exploration(compact:false).environment(\.colorScheme,.light))
    view.frame=NSRect(x:0,y:0,width:900,height:950)
    let window=NSWindow(contentRect:view.frame,styleMask:[.borderless],backing:.buffered,defer:false)
    window.contentView=view
    view.layoutSubtreeIfNeeded()
    if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) {
      view.cacheDisplay(in:view.bounds,to:bitmap)
      if let png=bitmap.representation(using:.png,properties:[:]) { try? png.write(to:URL(fileURLWithPath:CommandLine.arguments[1])) }
    }
 }
}
