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

// A resizable rounded-rect mask for NSVisualEffectView.maskImage — makes the
// frosted material (and thus the window shadow) take the rounded shape.
func roundedMask(radius: CGFloat) -> NSImage {
    let d = radius * 2 + 1
    let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    img.resizingMode = .stretch
    return img
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
        // Keep the dial subtitle short (just the plan) so it never collides
        // with the gauges. The full tier/stale detail lives in the text skin.
        var sub = pr["planLabel"] as? String ?? pr["plan"] as? String ?? ""
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

    // Natural (non-flipped) coordinates: y up. This makes circular drawing
    // behave normally — arcs sweep clockwise from the top as expected.
    override var isFlipped: Bool { false }

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
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let subAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor(white: 1, alpha: 0.55),
        ]

        var rowTop = bounds.height - rowGap / 2   // top of the first row
        for p in providers {
            let cy = rowTop - dialR                // vertical center of this row's dials
            // Provider name + subtitle (left column), centered on the row
            (p.name as NSString).draw(at: NSPoint(x: PAD, y: cy + 1), withAttributes: nameAttr)
            (p.subtitle as NSString).draw(
                with: NSRect(x: PAD, y: cy - 26, width: nameW + 70, height: 24),
                options: [.usesLineFragmentOrigin], attributes: subAttr)

            var x = PAD + nameW
            if p.windows.isEmpty {
                ("—" as NSString).draw(at: NSPoint(x: x, y: cy - 6), withAttributes: subAttr)
            }
            for w in p.windows {
                drawDial(cx: x + dialR, cy: cy, w: w, now: now)
                x += cellW
            }
            rowTop -= (cellH + rowGap)
        }
    }

    func drawDial(cx: CGFloat, cy: CGFloat, w: Win, now: Double) {
        let center = NSPoint(x: cx, y: cy)
        let outerR = dialR - ringW / 2

        // Track ring
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: outerR, startAngle: 0, endAngle: 360)
        NSColor(white: 1, alpha: 0.14).setStroke()
        track.lineWidth = ringW
        track.stroke()

        // Quota arc (remaining) — clockwise from the top (12 o'clock)
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

        // Pomodoro wedge: time remaining until reset, shrinking clockwise over
        // the window.
        if let reset = w.resetsAt {
            let remain = max(0, min(1, (reset - now) / windowSeconds(w)))
            let innerR = outerR - ringW - 2
            if remain > 0 && innerR > 2 {
                let wedge = NSBezierPath()
                wedge.move(to: center)
                wedge.appendArc(withCenter: center, radius: innerR,
                                startAngle: 90, endAngle: 90 - 360 * remain, clockwise: true)
                wedge.close()
                NSColor(white: 1, alpha: 0.13).setFill()
                wedge.fill()
            }
        }

        // Center: big remaining number with a smaller "%"
        let numStr = "\(Int(w.leftPercent.rounded()))" as NSString
        let numAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let pctAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: 0.7),
        ]
        let nsz = numStr.size(withAttributes: numAttr)
        let percentSz = ("%" as NSString).size(withAttributes: pctAttr)
        let totalW = nsz.width + percentSz.width
        let startX = cx - totalW / 2
        numStr.draw(at: NSPoint(x: startX, y: cy - nsz.height / 2 + 1), withAttributes: numAttr)
        ("%" as NSString).draw(at: NSPoint(x: startX + nsz.width, y: cy - nsz.height / 2 + 3), withAttributes: pctAttr)

        // Under-dial label:  "5h ↻ 40m"  (window name, then reset countdown —
        // the ↻ marks it as "resets in", not a fraction of the window)
        let cd = countdownString(w.resetsAt)
        let sub = "\(w.label)\(cd.isEmpty ? "" : " ↻ " + cd)" as NSString
        let subAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: 0.8),
        ]
        let sz = sub.size(withAttributes: subAttr)
        sub.draw(at: NSPoint(x: cx - sz.width / 2, y: cy - dialR - 12), withAttributes: subAttr)
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
    var statusItem: NSStatusItem!
    var tint: NSView!
    var latestProviders: [Provider] = []
    var lastUpdated: Date?
    let font = NSFont.monospacedSystemFont(ofSize: FONT_SIZE, weight: .regular)
    var skin: String { UserDefaults.standard.string(forKey: "skin") ?? "text" }
    var tintAlpha: CGFloat { CGFloat((UserDefaults.standard.object(forKey: "tintAlpha") as? Double) ?? 0.3) }

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
        let radius: CGFloat = 20   // iOS-style rounded glass
        blur.wantsLayer = true
        blur.layer?.cornerRadius = radius
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor(white: 1, alpha: 0.16).cgColor   // glass edge highlight
        // Mask the material itself to the rounded shape so the WINDOW SHADOW
        // follows the rounded corners instead of leaking as a rectangle.
        blur.maskImage = roundedMask(radius: radius)
        blur.appearance = NSAppearance(named: .darkAqua)
        w.contentView = blur
        self.blur = blur

        let tint = NSView(frame: blur.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.cornerRadius = radius
        tint.layer?.masksToBounds = true
        blur.addSubview(tint)
        self.tint = tint
        applyTint()

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
        w.invalidateShadow()
        self.window = w
        NSApp.setActivationPolicy(.accessory)

        // Menu-bar item — the discoverability anchor. Shows the tightest
        // remaining %, and its menu lists every window plus all actions and
        // their shortcuts.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            let img = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Usage")
                ?? NSImage(systemSymbolName: "gauge", accessibilityDescription: "Usage")
            img?.isTemplate = true
            btn.image = img
            btn.imagePosition = .imageLeading
            btn.title = " …"
        }

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
        startDataTimer()
    }

    func startDataTimer() {
        dataTimer?.invalidate()
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
            // Redraw every 30s only to keep the countdown / time-remaining wedge
            // current — not a spinning animation.
            animTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
                self.dial.needsDisplay = true
            }
        }
    }

    func refresh() {
        let isDial = skin == "dial"
        DispatchQueue.global(qos: .utility).async {
            let providers = parseProviders(runScript("--json"))
            let text = isDial ? "" : runScript("--once").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.latestProviders = providers
                self.lastUpdated = Date()
                if isDial { self.renderDial(providers) }
                else { self.renderText(text.isEmpty ? "(no output)" : text) }
                self.updateStatusAndMenu()
            }
        }
    }

    // --- Menu bar + context menu -------------------------------------------

    func updateStatusAndMenu() {
        let pcts = latestProviders.flatMap { $0.windows.map { $0.leftPercent } }
        statusItem.button?.title = pcts.min().map { " \(Int($0.rounded()))%" } ?? " –"
        let menu = buildMenu()
        statusItem.menu = menu
        blur.menu = menu   // same menu on right-click of the HUD
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        if latestProviders.isEmpty {
            let it = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            it.isEnabled = false; menu.addItem(it)
        }
        for p in latestProviders {
            let head = NSMenuItem(title: "\(p.name)  ·  \(p.subtitle)", action: nil, keyEquivalent: "")
            head.isEnabled = false
            menu.addItem(head)
            for w in p.windows {
                let cd = countdownString(w.resetsAt)
                let title = "    \(w.label)   \(Int(w.leftPercent.rounded()))% left" + (cd.isEmpty ? "" : "   ·   resets in \(cd)")
                let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                it.isEnabled = false
                menu.addItem(it)
            }
        }

        // Data freshness
        menu.addItem(.separator())
        let up = NSMenuItem(title: "Updated \(clockString(lastUpdated, seconds: true))", action: nil, keyEquivalent: "")
        up.isEnabled = false
        menu.addItem(up)
        let nx = NSMenuItem(title: "Next update \(clockString(dataTimer?.fireDate, seconds: false))", action: nil, keyEquivalent: "")
        nx.isEnabled = false
        menu.addItem(nx)

        menu.addItem(.separator())

        let skinItem = NSMenuItem(title: "Skin: \(skin == "dial" ? "Dial" : "Text")",
                                  action: #selector(menuToggleSkin), keyEquivalent: "t")
        skinItem.keyEquivalentModifierMask = .command; skinItem.target = self
        menu.addItem(skinItem)

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(menuRefresh), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = .command; refreshItem.target = self
        menu.addItem(refreshItem)

        let hideItem = NSMenuItem(title: window.isVisible ? "Hide HUD" : "Show HUD",
                                  action: #selector(menuToggleHUD), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        // Background opacity submenu (more/less see-through, remembered)
        let bgItem = NSMenuItem(title: "Background", action: nil, keyEquivalent: "")
        let bgMenu = NSMenu()
        for (label, val) in [("Clear", 0.12), ("Light", 0.30), ("Medium", 0.45), ("Solid", 0.65)] {
            let it = NSMenuItem(title: label, action: #selector(menuOpacity(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = val
            if abs(Double(tintAlpha) - val) < 0.01 { it.state = .on }
            bgMenu.addItem(it)
        }
        bgItem.submenu = bgMenu
        menu.addItem(bgItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command; quit.target = self
        menu.addItem(quit)
        return menu
    }

    func applyTint() { tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(tintAlpha).cgColor }

    @objc func menuOpacity(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? Double ?? 0.3, forKey: "tintAlpha")
        applyTint()
        updateStatusAndMenu()
    }
    @objc func menuToggleSkin() { toggleSkin() }
    @objc func menuRefresh() { startDataTimer(); refresh() }

    func clockString(_ d: Date?, seconds: Bool) -> String {
        guard let d = d else { return "—" }
        let f = DateFormatter()
        f.dateFormat = seconds ? "h:mm:ss a" : "h:mm a"
        return f.string(from: d)
    }
    @objc func menuToggleHUD() {
        if window.isVisible { window.orderOut(nil) } else { window.makeKeyAndOrderFront(nil) }
        updateStatusAndMenu()
    }
    @objc func menuQuit() { NSApp.terminate(nil) }

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
        // Recompute the drop shadow from the rounded content so it doesn't
        // leak as a rectangle at the 4 corners.
        window.invalidateShadow()
    }
}

let app = NSApplication.shared
let delegate = HUD()
app.delegate = delegate
app.run()
