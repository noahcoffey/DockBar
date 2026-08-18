import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var config: Config?
    private var poller: Poller?
    private var snapshot: Snapshot?

    private var pollTimer: Timer?
    private var isPolling = false
    private var pollGeneration = 0

    private var spinnerFrames: [NSImage] = []
    private var spinnerTimer: Timer?
    private var spinnerIndex = 0

    private lazy var idleIcon = Self.dokployIcon() ?? Self.symbolIcon("shippingbox")
    private lazy var errorIcon = Self.symbolIcon("exclamationmark.triangle")

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = idleIcon
        statusItem.button?.imagePosition = .imageLeft
        spinnerFrames = Self.makeSpinnerFrames()
        loadConfigAndStart(firstLaunch: true)
    }

    private func loadConfigAndStart(firstLaunch: Bool = false) {
        pollTimer?.invalidate()
        stopSpinner()
        pollGeneration += 1
        isPolling = false
        snapshot = nil
        config = nil
        poller = nil
        statusItem.button?.title = ""

        do {
            let config = try Config.load()
            self.config = config
            self.poller = Poller(config: config)
            statusItem.button?.image = idleIcon
            statusItem.menu = buildMenu()
            poll()
        } catch ConfigError.missing {
            try? Config.writeTemplate()
            statusItem.button?.image = idleIcon
            statusItem.menu = buildSetupMenu([
                "Welcome to DockBar!",
                "A starter config was created — fill in your",
                "Dokploy server URL and API key(s) to begin.",
            ])
            if firstLaunch { openConfigFile() }
        } catch ConfigError.notFilledIn {
            statusItem.button?.image = idleIcon
            statusItem.menu = buildSetupMenu([
                "Almost there — the config file still has",
                "placeholder values. Fill in your Dokploy",
                "server URL and API key(s), then reload.",
            ])
        } catch {
            let detail = (error as? ConfigError).flatMap {
                if case .invalid(let e) = $0 { return e.localizedDescription } else { return nil }
            } ?? error.localizedDescription
            statusItem.button?.image = errorIcon
            statusItem.menu = buildSetupMenu(["⚠️ Config file could not be parsed:", detail])
        }
    }

    // MARK: - Polling

    private func schedule(after interval: TimeInterval) {
        pollTimer?.invalidate()
        // .common mode so polling keeps running while the menu is open (event tracking)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func poll() {
        guard let poller, !isPolling else { return }
        isPolling = true
        let generation = pollGeneration
        Task {
            let snap = await poller.fetch()
            guard generation == self.pollGeneration else { return }
            self.isPolling = false
            self.apply(snap)
            self.schedule(after: snap.deploying.isEmpty ? (self.config?.idleInterval ?? 30) : 5)
        }
    }

    private func apply(_ snap: Snapshot) {
        snapshot = snap
        updateButton()
        statusItem.menu = buildMenu()
    }

    // MARK: - Status button

    private func updateButton() {
        guard let button = statusItem.button, let snap = snapshot else { return }
        if snap.deploying.isEmpty {
            stopSpinner()
            let hasError = snap.services.contains { $0.status == "error" }
            button.image = hasError ? errorIcon : idleIcon
            button.title = ""
        } else {
            let title: String
            if snap.deploying.count == 1 {
                title = " \(truncate(snap.deploying[0].name, 24)) deploying"
            } else {
                title = " \(snap.deploying.count) deploying"
            }
            button.title = title
            startSpinner()
        }
    }

    private func startSpinner() {
        guard spinnerTimer == nil else { return }
        // .common mode so the spinner keeps animating while the menu is open
        let timer = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.spinnerFrames.isEmpty else { return }
                self.spinnerIndex = (self.spinnerIndex + 1) % self.spinnerFrames.count
                self.statusItem.button?.image = self.spinnerFrames[self.spinnerIndex]
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        spinnerTimer = timer
    }

    private func stopSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        spinnerIndex = 0
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        guard let snap = snapshot else {
            menu.addItem(disabled("Loading…"))
            addFooter(to: menu)
            return menu
        }

        if snap.deploying.isEmpty {
            menu.addItem(disabled("All quiet — nothing deploying"))
        } else {
            for s in snap.deploying {
                let item = NSMenuItem(title: "🔄 \(s.name) (\(s.org)) — deploying…",
                                      action: #selector(openService(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = s.dashboardURL(serverUrl: config?.serverUrl ?? "")
                menu.addItem(item)
            }
        }

        for err in snap.orgErrors {
            menu.addItem(disabled("⚠️ \(err)"))
        }

        menu.addItem(.separator())
        addBrowseSection(to: menu, services: snap.services)

        menu.addItem(.separator())
        menu.addItem(disabled("Recent deployments"))

        if snap.recent.isEmpty {
            menu.addItem(disabled("None found"))
        } else {
            for entry in snap.recent {
                let glyph: String
                switch entry.deployment.status {
                case "done": glyph = "✅"
                case "error": glyph = "❌"
                case "running": glyph = "🔄"
                default: glyph = "⏺"
                }
                let ago = relativeFormatter.localizedString(for: entry.date, relativeTo: Date())
                let item = NSMenuItem(
                    title: "\(glyph) \(truncate(entry.service.name, 28)) (\(entry.service.org)) — \(ago)",
                    action: #selector(openService(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.service.dashboardURL(serverUrl: config?.serverUrl ?? "")
                var tip = entry.deployment.title ?? ""
                if let desc = entry.deployment.description, !desc.isEmpty {
                    tip += tip.isEmpty ? desc : "\n\(desc)"
                }
                item.toolTip = tip.isEmpty ? nil : tip
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(disabled("Updated \(DateFormatter.localizedString(from: snap.fetchedAt, dateStyle: .none, timeStyle: .medium))"))
        addFooter(to: menu)
        return menu
    }

    /// Adds an "Apps" browse tree: Org > Project > Service (leaves open the dashboard).
    /// With a single org the org level is skipped.
    private func addBrowseSection(to menu: NSMenu, services: [Service]) {
        menu.addItem(disabled("Apps"))
        guard !services.isEmpty else {
            menu.addItem(disabled("None found"))
            return
        }

        let byOrg = Dictionary(grouping: services, by: \.org)
        let orgNames = (config?.orgs.map(\.name) ?? []).filter { byOrg[$0] != nil }

        if orgNames.count == 1, let only = byOrg[orgNames[0]] {
            addProjectItems(to: menu, services: only)
        } else {
            for org in orgNames {
                let item = NSMenuItem(title: org, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                addProjectItems(to: submenu, services: byOrg[org] ?? [])
                item.submenu = submenu
                menu.addItem(item)
            }
        }
    }

    private func addProjectItems(to menu: NSMenu, services: [Service]) {
        let byProject = Dictionary(grouping: services, by: \.projectId)
        let sorted = byProject.values.sorted {
            ($0[0].projectName).localizedCaseInsensitiveCompare($1[0].projectName) == .orderedAscending
        }
        for projectServices in sorted {
            let item = NSMenuItem(title: projectServices[0].projectName, action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            let multiEnv = Set(projectServices.map(\.environmentId)).count > 1
            let ordered = projectServices.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            for s in ordered {
                let glyph: String
                switch s.status {
                case "done": glyph = "✅"
                case "error": glyph = "❌"
                case "running": glyph = "🔄"
                default: glyph = "⏺"
                }
                var title = "\(glyph) \(truncate(s.name, 28))"
                if multiEnv { title += " (\(s.environmentName))" }
                let serviceItem = NSMenuItem(title: title, action: #selector(openService(_:)), keyEquivalent: "")
                serviceItem.target = self
                serviceItem.representedObject = s.dashboardURL(serverUrl: config?.serverUrl ?? "")
                submenu.addItem(serviceItem)
            }
            item.submenu = submenu
            menu.addItem(item)
        }
    }

    private func addFooter(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(makeItem("Refresh Now", #selector(refreshNow), "r"))
        menu.addItem(makeItem("Open Dokploy", #selector(openDokploy), "o"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Open Config File", #selector(openConfigFile), ""))
        menu.addItem(makeItem("Reload Config", #selector(reloadConfig), ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit DockBar", #selector(quit), "q"))
    }

    private func buildSetupMenu(_ lines: [String]) -> NSMenu {
        let menu = NSMenu()
        for line in lines { menu.addItem(disabled(line)) }
        menu.addItem(disabled(Config.path.path))
        menu.addItem(.separator())
        menu.addItem(makeItem("Open Config File", #selector(openConfigFile), ""))
        menu.addItem(makeItem("Reload Config", #selector(reloadConfig), "r"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit DockBar", #selector(quit), "q"))
        return menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func openService(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func refreshNow() {
        poll()
    }

    @objc private func openConfigFile() {
        try? Config.writeTemplate()
        NSWorkspace.shared.open(Config.path)
    }

    @objc private func reloadConfig() {
        loadConfigAndStart()
    }

    @objc private func openDokploy() {
        if let base = config?.serverUrl, let url = URL(string: base) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Icons

    private func truncate(_ s: String, _ max: Int) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    private static func dokployIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "dokploy-icon", withExtension: "svg"),
              let svg = NSImage(contentsOf: url), svg.size.height > 0 else { return nil }
        let height: CGFloat = 17
        let size = NSSize(width: height * svg.size.width / svg.size.height, height: height)
        let icon = NSImage(size: size, flipped: false) { rect in
            svg.draw(in: rect)
            return true
        }
        icon.isTemplate = true
        return icon
    }

    private static func symbolIcon(_ name: String) -> NSImage {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: name) ?? NSImage()
        let configured = base.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? base
        configured.isTemplate = true
        return configured
    }

    private static func makeSpinnerFrames() -> [NSImage] {
        let base = symbolIcon("arrow.triangle.2.circlepath")
        return (0..<12).map { rotated(base, degrees: CGFloat($0) * -30) }
    }

    private static func rotated(_ image: NSImage, degrees: CGFloat) -> NSImage {
        let size = image.size
        let frame = NSImage(size: size, flipped: false) { rect in
            let transform = NSAffineTransform()
            transform.translateX(by: size.width / 2, yBy: size.height / 2)
            transform.rotate(byDegrees: degrees)
            transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
            transform.concat()
            image.draw(in: rect)
            return true
        }
        frame.isTemplate = true
        return frame
    }
}
