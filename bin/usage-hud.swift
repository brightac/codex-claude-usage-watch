// usage-hud — translucent, always-on-top floating HUD for `usage-watch`.
// Two skins (⌘T to switch, remembered):
//   • text  — the aligned monospaced `usage-watch --once` output
//   • dial  — circular gauges: an outer ring for remaining quota, a shrinking
//             pomodoro wedge for time-until-reset, and a second hand that
//             sweeps once a minute so the clock visibly turns on its own.
//
// Build:  swiftc -O usage-hud.swift -o ~/.local/bin/usage-hud -framework AppKit
// Run:    usage-hud &     (⌘T skin · ⌘R refresh · ⌘Q quit · drag to move)

import AppKit

let SCRIPT = "\"$HOME/.local/bin/usage-watch\""
let REFRESH_SECONDS = 300.0
let FONT_SIZE: CGFloat = 12.5
let PAD: CGFloat = 16.0

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

struct Win {
    let label: String
    let leftPercent: Double
    let resetsAt: Double?
    let windowMinutes: Double?
}
struct Provider {
    let name: String
    let subtitle: String   // plan / tier / stale / error
    let windows: [Win]
}

func runScript(_ args: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", "\(SCRIPT) \(args)"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do {
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    } catch { return "" }
}

func parseProviders(_ json: String) -> [Provider] {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = obj["providers"] as? [[String: Any]] else { return [] }
    return arr.map { pr in
        let name = pr["name"] as? String ?? "?"
        var sub = pr["plan"] as? String ?? ""
        if let tier = pr["tier"] as? String, !tier.isEmpty { sub += " · \(tier)" }
        if let s = pr["staleSec"] as? Double { sub += "  (cached \(ageString(s)))" }
        if let e = pr["error"] as? String { sub = e == "login" ? "not logged in" : e }
        let wins = (pr["windows"] as? [[String: Any]] ?? []).map { w in
            Win(label: w["label"] as? String ?? "",
                leftPercent: (w["leftPercent"] as? Double) ?? Double(w["leftPercent"] as? Int ?? 0),
                resetsAt: w["resetsAt"] as? Double,
                windowMinutes: (w["windowMinutes"] as? Double) ?? (w["windowMinutes"] as? Int).map(Double.init))
        }
        return Provider(name: name, subtitle: sub, windows: wins)
    }
}

func ageString(_ sec: Double) -> String {
    let s = Int(max(0, sec))
    if s < 60 { return "<1m ago" }
    let m = s / 60
    if m < 60 { return "\(m)m ago" }
    let h = m / 60
    if h < 24 { return "\(h)h \(m % 60)m ago" }
    return "\(h / 24)d \(h % 24)h ago"
}
func countdownString(_ resetsAt: Double?) -> String {
    guard let r = resetsAt else { return "" }
    var s = Int(max(0, r - Date().timeIntervalSince1970))
    let d = s / 86400; s %= 86400
    let h = s / 3600; s %= 3600
    let m = s / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
func windowSeconds(_ w: Win) -> Double {
    if let wm = w.windowMinutes, wm > 0 { return wm * 60 }
    return w.label.contains("5h") ? 300 * 60 : 10080 * 60   // fallback by label
}

// ---------------------------------------------------------------------------
// Dial view
// ---------------------------------------------------------------------------

final class DialView: NSView {
    var providers: [Provider] = [] { didSet { needsDisplay = true } }

    let dialR: CGFloat = 30
    let ringW: CGFloat = 6
    let cellGap: CGFloat = 14
    let nameW: CGFloat = 64
    let rowGap: CGFloat = 16
    let labelH: CGFloat = 16      // text under each dial
    var cellW: CGFloat { dialR * 2 + cellGap }
    var cellH: CGFloat { dialR * 2 + labelH }

    override var isFlipped: Bool { true }

    func contentSize() -> NSSize {
        var maxWins = 0
        for p in providers { maxWins = max(maxWins, max(1, p.windows.count)) }
        let w = nameW + CGFloat(maxWins) * cellW + PAD
        let h = CGFloat(providers.count) * (cellH + rowGap)
        return NSSize(width: max(240, w), height: max(80, h))
    }

    func color(_ pct: Double) -> NSColor {
        if pct >= 50 { return NSColor(calibratedRed: 0.32, green: 0.85, blue: 0.48, alpha: 1) }
        if pct >= 20 { return NSColor(calibratedRed: 1.0, green: 0.76, blue: 0.24, alpha: 1) }
        return NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.38, alpha: 1)
    }

    override func draw(_ dirty: NSRect) {
        let now = Date().timeIntervalSince1970
        var y = rowGap / 2
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let subAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor(white: 1, alpha: 0.55),
        ]

        for p in providers {
            // Provider name + subtitle (left column)
            (p.name as NSString).draw(at: NSPoint(x: PAD, y: y + dialR - 12), withAttributes: nameAttr)
            (p.subtitle as NSString).draw(
                with: NSRect(x: PAD, y: y + dialR + 4, width: nameW + 40, height: 28),
                options: [.usesLineFragmentOrigin], attributes: subAttr)

            var x = PAD + nameW
            if p.windows.isEmpty {
                ("—" as NSString).draw(at: NSPoint(x: x, y: y + dialR - 8), withAttributes: subAttr)
            }
            for w in p.windows {
                drawDial(centerX: x + dialR, centerY: y + dialR, w: w, now: now)
                x += cellW
            }
            y += cellH + rowGap
        }
    }

    func drawDial(centerX cx: CGFloat, centerY cy: CGFloat, w: Win, now: Double) {
        let center = NSPoint(x: cx, y: cy)
        let outerR = dialR - ringW / 2

        // Track ring
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: outerR, startAngle: 0, endAngle: 360)
        NSColor(white: 1, alpha: 0.14).setStroke()
        track.lineWidth = ringW
        track.stroke()

        // Quota arc (remaining), from top clockwise
        let frac = max(0, min(1, w.leftPercent / 100))
        if frac > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: outerR,
                          startAngle: 90, endAngle: 90 - 360 * frac, clockwise: true)
            color(w.leftPercent).setStroke()
            arc.lineWidth = ringW
            arc.lineCapStyle = .round
            arc.stroke()
        }

        // Pomodoro wedge: time remaining until reset (shrinks over the window)
        if let reset = w.resetsAt {
            let remain = max(0, min(1, (reset - now) / windowSeconds(w)))
            let innerR = outerR - ringW - 2
            if remain > 0 && innerR > 2 {
                let wedge = NSBezierPath()
                wedge.move(to: center)
                wedge.appendArc(withCenter: center, radius: innerR,
                                startAngle: 90, endAngle: 90 - 360 * remain, clockwise: true)
                wedge.close()
                NSColor(white: 1, alpha: 0.12).setFill()
                wedge.fill()
            }
        }

        // Second hand — sweeps once a minute so the clock visibly turns.
        let secs = now.truncatingRemainder(dividingBy: 60)
        let handAngle = (90 - secs / 60 * 360) * .pi / 180
        let handR = outerR - ringW - 3
        if handR > 3 {
            let hand = NSBezierPath()
            hand.move(to: center)
            hand.line(to: NSPoint(x: cx + cos(handAngle) * handR, y: cy + sin(handAngle) * handR))
            NSColor(white: 1, alpha: 0.5).setStroke()
            hand.lineWidth = 1.3
            hand.lineCapStyle = .round
            hand.stroke()
        }
        // Hub dot
        let hub = NSBezierPath(ovalIn: NSRect(x: cx - 2, y: cy - 2, width: 4, height: 4))
        NSColor(white: 1, alpha: 0.7).setFill()
        hub.fill()

        // Under-dial label:  "5h 42% 40m"  (quota number + reset countdown;
        // the ring shows the quota, the wedge/hand show the time).
        let cd = countdownString(w.resetsAt)
        let sub = "\(w.label) \(Int(w.leftPercent.rounded()))%\(cd.isEmpty ? "" : " " + cd)" as NSString
        let subAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.8),
        ]
        let sz = sub.size(withAttributes: subAttr)
        sub.draw(at: NSPoint(x: cx - sz.width / 2, y: cy + dialR + 1), withAttributes: subAttr)
    }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

final class HUD: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var blur: NSVisualEffectView!
    var label: NSTextField!          // text skin
    var dial: DialView!              // dial skin
    var dataTimer: Timer?
    var animTimer: Timer?
    let font = NSFont.monospacedSystemFont(ofSize: FONT_SIZE, weight: .regular)
    var skin: String { UserDefaults.standard.string(forKey: "skin") ?? "text" }

    func applicationDidFinishLaunching(_: Notification) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
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
        blur.appearance = NSAppearance(named: .darkAqua)
        w.contentView = blur
        self.blur = blur

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
        tf.drawsBackground = false
        tf.isBezeled = false
        tf.isEditable = false
        tf.isSelectable = false
        tf.maximumNumberOfLines = 0
        blur.addSubview(tf)
        self.label = tf

        let dv = DialView(frame: .zero)
        blur.addSubview(dv)
        self.dial = dv

        if !w.setFrameUsingName("UsageHUD") { w.center() }
        w.setFrameAutosaveName("UsageHUD")
        w.makeKeyAndOrderFront(nil)
        self.window = w
        NSApp.setActivationPolicy(.accessory)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.modifierFlags.contains(.command) {
                switch e.charactersIgnoringModifiers {
                case "q": NSApp.terminate(nil); return nil
                case "r": self.refresh(); return nil
                case "t": self.toggleSkin(); return nil
                default: break
                }
            }
            return e
        }

        applySkin()
        refresh()
        dataTimer = Timer.scheduledTimer(withTimeInterval: REFRESH_SECONDS, repeats: true) { _ in self.refresh() }
    }

    func toggleSkin() {
        UserDefaults.standard.set(skin == "text" ? "dial" : "text", forKey: "skin")
        applySkin()
        refresh()
    }

    // Show the right subview and (for dial) run a 1s animation timer.
    func applySkin() {
        let isDial = skin == "dial"
        label.isHidden = isDial
        dial.isHidden = !isDial
        animTimer?.invalidate(); animTimer = nil
        if isDial {
            animTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.dial.needsDisplay = true
            }
        }
    }

    func refresh() {
        let isDial = skin == "dial"
        DispatchQueue.global(qos: .utility).async {
            if isDial {
                let providers = parseProviders(runScript("--json"))
                DispatchQueue.main.async { self.renderDial(providers) }
            } else {
                let out = runScript("--once").trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async { self.renderText(out.isEmpty ? "(no output)" : out) }
            }
        }
    }

    func renderText(_ text: String) {
        label.stringValue = text
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        var maxW: CGFloat = 0
        for line in lines {
            let lw = (line as NSString).size(withAttributes: attrs).width
            if lw > maxW { maxW = lw }
        }
        let sz = NSSize(width: ceil(maxW) + PAD * 2 + 4,
                        height: ceil(CGFloat(lines.count) * lineHeight) + PAD * 2)
        resize(to: sz)
        label.frame = NSRect(x: PAD, y: PAD, width: sz.width - PAD * 2, height: sz.height - PAD * 2)
    }

    func renderDial(_ providers: [Provider]) {
        dial.providers = providers
        let cs = dial.contentSize()
        let sz = NSSize(width: cs.width + PAD, height: cs.height + PAD)
        resize(to: sz)
        dial.frame = NSRect(x: PAD / 2, y: PAD / 2, width: sz.width - PAD, height: sz.height - PAD)
        dial.needsDisplay = true
    }

    // Resize keeping the top-left corner fixed.
    func resize(to size: NSSize) {
        let top = window.frame.maxY
        var f = window.frame
        f.size = NSSize(width: max(240, size.width), height: max(70, size.height))
        f.origin.y = top - f.size.height
        window.setFrame(f, display: true, animate: false)
    }
}

let app = NSApplication.shared
let delegate = HUD()
app.delegate = delegate
app.run()
