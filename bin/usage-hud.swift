// usage-hud — a translucent, always-on-top floating HUD that shows the output
// of `usage-watch --once`, refreshing on an interval. Native AppKit, no deps.
//
// Build:  swiftc -O usage-hud.swift -o ~/.local/bin/usage-hud -framework AppKit
// Run:    usage-hud &        (⌘Q to quit; drag anywhere to move)

import AppKit

// Resolved through a login shell, so ~/.local/bin is on PATH for any user.
let SCRIPT = "\"$HOME/.local/bin/usage-watch\""
let REFRESH_SECONDS = 300.0
let FONT_SIZE: CGFloat = 12.5
let PAD: CGFloat = 16.0

final class HUD: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var label: NSTextField!
    var timer: Timer?
    let font = NSFont.monospacedSystemFont(ofSize: FONT_SIZE, weight: .regular)

    func applicationDidFinishLaunching(_: Notification) {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 210),
            styleMask: [.borderless], backing: .buffered, defer: false)
        w.level = .floating
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.isMovableByWindowBackground = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let blur = NSVisualEffectView(frame: w.contentView!.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        blur.appearance = NSAppearance(named: .darkAqua)   // keep the frost dark
        w.contentView = blur

        // Fixed dark tint on top of the blur so white text stays legible on ANY
        // background (light wallpaper, white window behind, etc.) — like the
        // system volume HUD. Still translucent.
        let tint = NSView(frame: blur.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        tint.layer?.cornerRadius = 14
        tint.layer?.masksToBounds = true
        blur.addSubview(tint)

        let tf = NSTextField(wrappingLabelWithString: "Loading…")
        tf.font = font
        tf.textColor = .white
        tf.backgroundColor = .clear
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.isEditable = false
        tf.isSelectable = false
        tf.maximumNumberOfLines = 0
        tf.frame = NSRect(x: PAD, y: PAD, width: 620 - PAD * 2, height: 210 - PAD * 2)
        blur.addSubview(tf)
        self.label = tf
        self.window = w

        // Restore last position, or center on first ever launch.
        if !w.setFrameUsingName("UsageHUD") { w.center() }
        w.setFrameAutosaveName("UsageHUD")   // remembers position across launches
        w.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.accessory)   // no Dock icon

        // ⌘Q to quit, ⌘R to force refresh
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.modifierFlags.contains(.command) {
                if e.charactersIgnoringModifiers == "q" { NSApp.terminate(nil); return nil }
                if e.charactersIgnoringModifiers == "r" { self.refresh(); return nil }
            }
            return e
        }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: REFRESH_SECONDS, repeats: true) { _ in
            self.refresh()
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // -l sources the login profile so node/security/codex resolve exactly
            // as they do in the user's terminal.
            p.arguments = ["-lc", "\(SCRIPT) --once"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            var out = "(failed to run usage-watch)"
            do {
                try p.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                out = String(data: data, encoding: .utf8) ?? out
            } catch { out = "error: \(error)" }
            let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { self.render(text) }
        }
    }

    func render(_ text: String) {
        label.stringValue = text
        // Size to content by measuring each line explicitly — line count times the
        // exact line height. (boundingRect under-measured multiline height and
        // clipped the bottom rows.) Keep the top-left corner fixed.
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        var maxW: CGFloat = 0
        for line in lines {
            let lw = (line as NSString).size(withAttributes: attrs).width
            if lw > maxW { maxW = lw }
        }
        let newW = ceil(maxW) + PAD * 2 + 4   // small fudge so no line wraps at the edge
        let newH = ceil(CGFloat(lines.count) * lineHeight) + PAD * 2
        let top = window.frame.maxY
        var f = window.frame
        f.size = NSSize(width: max(260, newW), height: max(60, newH))
        f.origin.y = top - f.size.height
        window.setFrame(f, display: true, animate: false)
        label.frame = NSRect(x: PAD, y: PAD, width: f.size.width - PAD * 2, height: f.size.height - PAD * 2)
    }
}

let app = NSApplication.shared
let delegate = HUD()
app.delegate = delegate
app.run()
