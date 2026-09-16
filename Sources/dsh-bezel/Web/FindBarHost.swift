import AppKit
import WebKit

/// The browser-style find bar pinned over the page.
///
/// Highlights matching text directly across the entire document:
/// - Works reliably on standard text, inline `<code>` (even with `display: inline-flex`),
///   `<pre>`, code blocks, and conversation history.
/// - Highlights ALL candidate matches in high-contrast vivid bright yellow (`#ffe033` with `#000000` text)
/// - Highlights the CURRENT active match in prominent vivid bright orange (`#ff6b00` with `#ffffff` text)
/// - Smoothly scrolls matches into view across all nested containers (`overflow-y: auto`)
/// - Displays real-time browser-style match counts ("1/12", "0/0")
final class FindBarHost: NSView, NSSearchFieldDelegate {
    /// Called when the user closes the find bar via the Done button or Escape.
    var onVisibilityChange: ((Bool) -> Void)?

    weak var webView: WKWebView?

    private(set) var isFindBarVisible = false

    private let searchField = FindSearchField()
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let doneButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.12).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Find"
        searchField.delegate = self
        searchField.onEscape = { [weak self] in
            self?.hide()
        }
        searchField.onReturn = { [weak self] backwards in
            self?.navigate(backwards: backwards)
        }

        prevButton.translatesAutoresizingMaskIntoConstraints = false
        prevButton.bezelStyle = .inline
        prevButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous Match")
        prevButton.target = self
        prevButton.action = #selector(findPrevious)

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.bezelStyle = .inline
        nextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next Match")
        nextButton.target = self
        nextButton.action = #selector(findNext)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.bezelStyle = .inline
        doneButton.title = "Done"
        doneButton.target = self
        doneButton.action = #selector(hide)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [searchField, statusLabel, prevButton, nextButton, doneButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            heightAnchor.constraint(equalToConstant: 36)
        ])

        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("FindBarHost is created in code")
    }

    // MARK: Actions

    func show(focus: Bool = true) {
        guard !isFindBarVisible else {
            if focus {
                window?.makeFirstResponder(searchField)
            }
            return
        }
        isFindBarVisible = true
        isHidden = false
        onVisibilityChange?(true)
        if focus {
            window?.makeFirstResponder(searchField)
            if !searchField.stringValue.isEmpty {
                searchField.currentEditor()?.selectAll(nil)
            }
        }
        if !searchField.stringValue.isEmpty {
            performSearch(query: searchField.stringValue)
        }
    }

    @objc func hide() {
        guard isFindBarVisible else { return }
        isFindBarVisible = false
        isHidden = true
        statusLabel.stringValue = ""
        clearHighlight()
        onVisibilityChange?(false)
    }

    @objc func findNext() {
        navigate(backwards: false)
    }

    @objc func findPrevious() {
        navigate(backwards: true)
    }

    func setSearchText(_ text: String) {
        searchField.stringValue = text
        show(focus: true)
        performSearch(query: text)
    }

    func updateLocalizedLabels(placeholder: String, doneTitle: String) {
        searchField.placeholderString = placeholder
        doneButton.title = doneTitle
    }

    // MARK: Search Engine & Highlights

    private func performSearch(query: String) {
        guard let webView else { return }
        guard !query.isEmpty else {
            statusLabel.stringValue = ""
            clearHighlight()
            return
        }

        let escapedQuery = query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let script = """
        (() => {
            if (!window.__dshFindEngine) {
                window.__dshFindEngine = {
                    currentIndex: -1,
                    
                    ensureStyle() {
                        if (!document.getElementById('__dsh_find_style__')) {
                            const style = document.createElement('style');
                            style.id = '__dsh_find_style__';
                            style.textContent = `
                                mark.dsh-find-match {
                                    background-color: #ffe033 !important;
                                    color: #000000 !important;
                                    padding: 0 !important;
                                    margin: 0 !important;
                                    border-radius: 2px !important;
                                }
                                mark.dsh-find-current {
                                    background-color: #ff6b00 !important;
                                    color: #ffffff !important;
                                    padding: 0 !important;
                                    margin: 0 !important;
                                    border-radius: 2px !important;
                                }
                            `;
                            document.head.appendChild(style);
                        }
                    },
                    
                    clear() {
                        const marks = document.querySelectorAll('mark.dsh-find-match, mark.dsh-find-current');
                        marks.forEach(m => {
                            const parent = m.parentNode;
                            if (parent) {
                                while (m.firstChild) {
                                    parent.insertBefore(m.firstChild, m);
                                }
                                parent.removeChild(m);
                                parent.normalize();
                            }
                        });
                        this.currentIndex = -1;
                    },
                    
                    search(query) {
                        this.clear();
                        if (!query || query.length === 0) return { count: 0, current: 0 };
                        
                        this.ensureStyle();
                        
                        const lowerQuery = query.toLowerCase();
                        const qLen = query.length;
                        
                        const treeWalker = document.createTreeWalker(
                            document.body,
                            NodeFilter.SHOW_TEXT,
                            {
                                acceptNode(node) {
                                    if (!node.nodeValue) return NodeFilter.FILTER_REJECT;
                                    const p = node.parentElement;
                                    if (!p) return NodeFilter.FILTER_ACCEPT;
                                    const tag = p.tagName.toLowerCase();
                                    if (tag === 'script' || tag === 'style' || tag === 'noscript' || tag === 'mark') {
                                        return NodeFilter.FILTER_REJECT;
                                    }
                                    return NodeFilter.FILTER_ACCEPT;
                                }
                            }
                        );
                        
                        let node = treeWalker.nextNode();
                        const matches = [];
                        while (node) {
                            const text = node.nodeValue;
                            const lowerText = text.toLowerCase();
                            let idx = lowerText.indexOf(lowerQuery);
                            while (idx !== -1) {
                                matches.push({ node, idx });
                                idx = lowerText.indexOf(lowerQuery, idx + qLen);
                            }
                            node = treeWalker.nextNode();
                        }
                        
                        // Wrap matches in reverse order so DOM text offsets stay valid
                        for (let i = matches.length - 1; i >= 0; i--) {
                            const m = matches[i];
                            const range = new Range();
                            try {
                                range.setStart(m.node, m.idx);
                                range.setEnd(m.node, m.idx + qLen);
                                const mark = document.createElement('mark');
                                mark.className = 'dsh-find-match';
                                range.surroundContents(mark);
                            } catch (e) {}
                        }
                        
                        const createdMarks = document.querySelectorAll('mark.dsh-find-match');
                        const total = createdMarks.length;
                        if (total > 0) {
                            this.currentIndex = 0;
                            this.updateActive();
                        }
                        
                        return { count: total, current: total > 0 ? 1 : 0 };
                    },
                    
                    next() {
                        const marks = document.querySelectorAll('mark.dsh-find-match, mark.dsh-find-current');
                        if (marks.length === 0) return { count: 0, current: 0 };
                        this.currentIndex = (this.currentIndex + 1) % marks.length;
                        this.updateActive();
                        return { count: marks.length, current: this.currentIndex + 1 };
                    },
                    
                    previous() {
                        const marks = document.querySelectorAll('mark.dsh-find-match, mark.dsh-find-current');
                        if (marks.length === 0) return { count: 0, current: 0 };
                        this.currentIndex = (this.currentIndex - 1 + marks.length) % marks.length;
                        this.updateActive();
                        return { count: marks.length, current: this.currentIndex + 1 };
                    },
                    
                    updateActive() {
                        const marks = document.querySelectorAll('mark.dsh-find-match, mark.dsh-find-current');
                        if (marks.length === 0) return;
                        
                        marks.forEach((m, idx) => {
                            if (idx === this.currentIndex) {
                                m.className = 'dsh-find-current';
                                m.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' });
                            } else {
                                m.className = 'dsh-find-match';
                            }
                        });
                    }
                };
            }
            
            return window.__dshFindEngine.search("\(escapedQuery)");
        })()
        """

        webView.evaluateJavaScript(script) { [weak self] res, _ in
            DispatchQueue.main.async {
                guard let dict = res as? [String: Any],
                      let count = dict["count"] as? Int,
                      let current = dict["current"] as? Int else {
                    self?.statusLabel.stringValue = ""
                    return
                }
                if count == 0 {
                    self?.statusLabel.stringValue = "0/0"
                } else {
                    self?.statusLabel.stringValue = "\(current)/\(count)"
                }
            }
        }
    }

    private func navigate(backwards: Bool) {
        guard let webView, isFindBarVisible else { return }
        let action = backwards ? "previous" : "next"
        let script = "window.__dshFindEngine ? window.__dshFindEngine.\(action)() : { count: 0, current: 0 }"

        webView.evaluateJavaScript(script) { [weak self] res, _ in
            DispatchQueue.main.async {
                guard let dict = res as? [String: Any],
                      let count = dict["count"] as? Int,
                      let current = dict["current"] as? Int else {
                    return
                }
                if count == 0 {
                    self?.statusLabel.stringValue = "0/0"
                } else {
                    self?.statusLabel.stringValue = "\(current)/\(count)"
                }
            }
        }
    }

    private func clearHighlight() {
        webView?.evaluateJavaScript("window.__dshFindEngine && window.__dshFindEngine.clear()")
    }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        performSearch(query: searchField.stringValue)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isFindBarVisible else { return nil }
        return super.hitTest(point)
    }
}

private final class FindSearchField: NSSearchField {
    var onEscape: (() -> Void)?
    var onReturn: ((_ backwards: Bool) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            onEscape?()
            return true
        }
        if event.keyCode == 36 { // Return / Enter
            let isShift = event.modifierFlags.contains(.shift)
            onReturn?(isShift)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
