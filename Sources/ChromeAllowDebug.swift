import AppKit
import ApplicationServices

// ChromeAllowDebug — auto-approves ONLY the native "Allow remote debugging?"
// consent sheet that Chromium browsers show when an external app attaches over
// the DevTools/CDP protocol. It presses that sheet's "Allow" button via the
// macOS Accessibility API.
//
// Safety: it acts only on a modal AXSheet whose text contains "debug" AND only
// presses a button whose accessible label is exactly "Allow". Web permission
// bubbles (location/notifications/camera) are not AXSheets, and other native
// sheets (print/save/etc.) don't contain that text — so nothing else is touched.

// Chromium-family browsers that show the "Allow remote debugging?" sheet.
let targetBundleIDs: Set<String> = [
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.google.Chrome.canary",
    "com.google.Chrome.dev",
    "org.chromium.Chromium",
    "com.brave.Browser",
    "com.brave.Browser.beta",
    "com.brave.Browser.nightly",
    "com.microsoft.edgemac",
    "com.microsoft.edgemac.Beta",
    "com.vivaldi.Vivaldi",
    "com.operasoftware.Opera",
]

let pollInterval: TimeInterval = 1.0

@inline(__always)
func copyAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

func strAttr(_ el: AXUIElement, _ attr: String) -> String? { copyAttr(el, attr) as? String }

func elArray(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
    guard let v = copyAttr(el, attr), CFGetTypeID(v) == CFArrayGetTypeID(),
          let arr = v as? [AXUIElement] else { return [] }
    return arr
}

func role(_ el: AXUIElement) -> String { strAttr(el, kAXRoleAttribute as String) ?? "" }

func children(_ el: AXUIElement) -> [AXUIElement] { elArray(el, kAXChildrenAttribute as String) }

// Bounded depth-first collection of descendants.
func collect(_ el: AXUIElement, depth: Int, maxDepth: Int, into acc: inout [AXUIElement]) {
    if depth >= maxDepth { return }
    for c in children(el) {
        acc.append(c)
        collect(c, depth: depth + 1, maxDepth: maxDepth, into: &acc)
    }
}

let logDF: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

func log(_ msg: String) {
    let line = "[\(logDF.string(from: Date()))] \(msg)\n"
    FileHandle.standardOutput.write(line.data(using: .utf8)!)
}

func targetApps() -> [(name: String, el: AXUIElement)] {
    NSWorkspace.shared.runningApplications
        .filter { targetBundleIDs.contains($0.bundleIdentifier ?? "") }
        .map { ($0.localizedName ?? $0.bundleIdentifier ?? "?",
                AXUIElementCreateApplication($0.processIdentifier)) }
}

// Returns true if it pressed an Allow button this pass.
func tryApproveOnce() -> Bool {
    var pressed = false
    for app in targetApps() {
        for w in elArray(app.el, kAXWindowsAttribute as String) {
            // Sheets are shallow children of the window.
            var shallow: [AXUIElement] = []
            collect(w, depth: 0, maxDepth: 3, into: &shallow)
            for sheet in shallow where role(sheet) == "AXSheet" {
                var desc: [AXUIElement] = []
                collect(sheet, depth: 0, maxDepth: 12, into: &desc)

                // Guard: only the remote-debugging sheet mentions "debug".
                let looksLikeDebug = desc.contains { el in
                    guard role(el) == "AXStaticText" else { return false }
                    let text = (strAttr(el, kAXValueAttribute as String) ?? "") + " "
                             + (strAttr(el, kAXTitleAttribute as String) ?? "")
                    return text.lowercased().contains("debug")
                }
                guard looksLikeDebug else { continue }

                for el in desc where role(el) == "AXButton" {
                    let title = strAttr(el, kAXTitleAttribute as String) ?? ""
                    let adesc = strAttr(el, kAXDescriptionAttribute as String) ?? ""
                    if title == "Allow" || adesc == "Allow" {
                        let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
                        if r == .success {
                            log("Approved remote-debugging dialog in \(app.name).")
                            pressed = true
                        } else {
                            log("Found Allow button in \(app.name) but AXPress failed (code \(r.rawValue)).")
                        }
                    }
                }
            }
        }
    }
    return pressed
}

// Register with / prompt for Accessibility so the app appears in the list.
let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
log("ChromeAllowDebug started. Accessibility trusted = \(trusted). Watching every \(pollInterval)s.")

var warnedUntrusted = false
while true {
    if !AXIsProcessTrusted() {
        if !warnedUntrusted {
            log("NOT trusted for Accessibility yet — enable ChromeAllowDebug in "
              + "System Settings › Privacy & Security › Accessibility.")
            warnedUntrusted = true
        }
    } else {
        if warnedUntrusted { log("Accessibility granted — now watching.") }
        warnedUntrusted = false
        _ = tryApproveOnce()
    }
    Thread.sleep(forTimeInterval: pollInterval)
}
