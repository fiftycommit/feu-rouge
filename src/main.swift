import Cocoa

// MARK: - Modele

enum Light: Int {
    case none = 0      // gris  : aucun codex
    case idle = 1      // vert  : dispo
    case running = 2   // jaune : en train de tourner
    case waiting = 3   // rouge : attend une action

    var color: NSColor {
        switch self {
        case .none:    return NSColor(white: 0.56, alpha: 0.5)
        case .idle:    return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .running: return NSColor(red: 1.00, green: 0.74, blue: 0.10, alpha: 1)
        case .waiting: return NSColor(red: 1.00, green: 0.27, blue: 0.23, alpha: 1)
        }
    }

    var label: String {
        switch self {
        case .none:    return "aucune session"
        case .idle:    return "disponible"
        case .running: return "en cours"
        case .waiting: return "attend une action"
        }
    }

    static func from(_ s: String) -> Light {
        switch s {
        case "waiting": return .waiting
        case "running": return .running
        default:        return .idle
        }
    }
}

/// Chaque agent a sa forme, pour les distinguer sans ouvrir le menu.
enum Agent: String {
    case codex, claude, antigravity, omp

    var label: String {
        switch self {
        case .codex:       return "codex"
        case .claude:      return "claude"
        case .antigravity: return "antigravity"
        case .omp:         return "omp"
        }
    }

    /// codex = rond, claude = carre arrondi, antigravity = losange, omp = triangle.
    func path(in r: NSRect) -> NSBezierPath {
        switch self {
        case .codex:
            return NSBezierPath(ovalIn: r)
        case .claude:
            return NSBezierPath(roundedRect: r.insetBy(dx: 0.4, dy: 0.4), xRadius: 3, yRadius: 3)
        case .omp:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.midX, y: r.maxY))
            p.line(to: NSPoint(x: r.maxX, y: r.minY))
            p.line(to: NSPoint(x: r.minX, y: r.minY))
            p.close()
            return p
        case .antigravity:
            let p = NSBezierPath()
            let d = r.insetBy(dx: -0.7, dy: -0.7)
            p.move(to: NSPoint(x: d.midX, y: d.maxY))
            p.line(to: NSPoint(x: d.maxX, y: d.midY))
            p.line(to: NSPoint(x: d.midX, y: d.minY))
            p.line(to: NSPoint(x: d.minX, y: d.midY))
            p.close()
            return p
        }
    }

    static func from(_ s: String?) -> Agent { Agent(rawValue: s ?? "") ?? .codex }
}

struct Session {
    let id: String
    let light: Light
    let agent: Agent
    let cwd: String
    let pid: pid_t
    let ts: Date

    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "~" : name
    }
}

// MARK: - Lecture de l'etat

final class StateReader {
    let dir: URL

    init() {
        let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/state")
        dir = base.appendingPathComponent("codex-feu-rouge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Sessions vivantes. Les fichiers orphelins (process mort, ou trop vieux)
    /// sont supprimes au passage.
    func sessions() -> [Session] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir,
                                                      includingPropertiesForKeys: nil) else { return [] }
        var out: [Session] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let state = obj["state"] as? String
            else { try? fm.removeItem(at: url); continue }

            let pid = pid_t((obj["pid"] as? NSNumber)?.int32Value ?? 0)
            let ts = Date(timeIntervalSince1970: (obj["ts"] as? NSNumber)?.doubleValue ?? 0)

            // Session morte : le process codex n'existe plus.
            if pid > 0 && kill(pid, 0) != 0 && errno == ESRCH {
                try? fm.removeItem(at: url)
                continue
            }
            // Garde-fou : rien depuis 24 h.
            if Date().timeIntervalSince(ts) > 86_400 {
                try? fm.removeItem(at: url)
                continue
            }

            out.append(Session(id: url.deletingPathExtension().lastPathComponent,
                               light: Light.from(state),
                               agent: Agent.from(obj["agent"] as? String),
                               cwd: obj["cwd"] as? String ?? "",
                               pid: pid,
                               ts: ts))
        }
        // Ordre stable : les pastilles ne dansent pas d'un refresh a l'autre.
        return out.sorted { $0.id < $1.id }
    }
}

// MARK: - App

final class Controller: NSObject {
    /// Cle du placeholder gris affiche quand aucune session ne tourne.
    private static let placeholderKey = "\u{0}aucune"

    private let reader = StateReader()
    private var items: [String: NSStatusItem] = [:]
    private var signature = ""
    private var timer: Timer?

    override init() {
        super.init()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // Pastille dessinee a la main : couleur pleine + leger anneau pour le contraste.
    private static func dot(for light: Light, agent: Agent = .codex) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        let rect = NSRect(x: 2.5, y: 2.5, width: 11, height: 11)
        let path = agent.path(in: rect)
        light.color.setFill()
        path.fill()
        NSColor.black.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private func refresh() {
        let sessions = reader.sessions()
        let sig = sessions.isEmpty
            ? "vide"
            : sessions.map { "\($0.id):\($0.light.rawValue):\($0.agent.rawValue):\($0.project)" }.joined(separator: ",")
        guard sig != signature else { return }
        signature = sig

        if sessions.isEmpty {
            prune(keeping: [Controller.placeholderKey])
            apply(to: item(for: Controller.placeholderKey),
                  light: .none, agent: .codex, title: "Aucun agent actif", path: nil)
        } else {
            prune(keeping: Set(sessions.map(\.id)))
            for s in sessions {
                apply(to: item(for: s.id),
                      light: s.light,
                      agent: s.agent,
                      title: "\(s.agent.label) · \(s.project) — \(s.light.label)",
                      path: s.cwd)
            }
        }
        debugDump()
    }

    /// Retire les pastilles dont la session a disparu.
    private func prune(keeping keep: Set<String>) {
        for (key, it) in items where !keep.contains(key) {
            NSStatusBar.system.removeStatusItem(it)
            items.removeValue(forKey: key)
        }
    }

    private func item(for key: String) -> NSStatusItem {
        if let existing = items[key] { return existing }
        let it = NSStatusBar.system.statusItem(withLength: 24)
        it.button?.imagePosition = .imageOnly
        it.menu = NSMenu()
        items[key] = it
        return it
    }

    private func apply(to it: NSStatusItem, light: Light, agent: Agent, title: String, path: String?) {
        it.button?.image = Controller.dot(for: light, agent: agent)
        it.button?.toolTip = path ?? title

        guard let menu = it.menu else { return }
        menu.removeAllItems()

        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let path {
            let loc = NSMenuItem(title: path, action: #selector(reveal(_:)), keyEquivalent: "")
            loc.target = self
            loc.representedObject = path
            menu.addItem(loc)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter FeuRouge", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func reveal(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func debugDump() {
        guard ProcessInfo.processInfo.environment["FEUROUGE_DEBUG"] == "1" else { return }
        let frames = items.map { "\($0.key.prefix(8))=\(String(describing: $0.value.button?.window?.frame.origin.x))" }
        FileHandle.standardError.write("pastilles: \(frames.joined(separator: " "))\n".data(using: .utf8)!)
    }
}

// Instance unique : un verrou exclusif, sinon on aurait un jeu de pastilles par
// exemplaire lance. Le fd reste ouvert pour toute la duree du process.
func claimSingleInstance() {
    let lock = NSTemporaryDirectory() + "fr.max.feurouge.lock"
    let fd = open(lock, O_CREAT | O_RDWR, 0o644)
    guard fd >= 0 else { return }
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        FileHandle.standardError.write("FeuRouge tourne deja.\n".data(using: .utf8)!)
        exit(0)
    }
}

claimSingleInstance()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = Controller()
app.run()
