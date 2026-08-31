import JavaScriptKit
import Core

/// Renders the session list into a container element: one row per frame,
/// appended live as frames arrive. Completed responses can be opened as a
/// reconstructed raw HTTP message in a modal dialog.
final class SessionListRenderer {
    private let tableBody: JSObject
    private let responseDialog: ResponseDialog = .init()

    init(containerID: String) {
        // Try to reuse existing table from HTML, or create new one
        let table: JSObject
        if let existingTable = JSHelper.byID("reedpipe-session-table") {
            table = existingTable
        } else {
            table = JSHelper.createElement("table")
            JSHelper.setID(table, "reedpipe-session-table")

            let thead = JSHelper.createElement("thead")
            let headerRow = JSHelper.createElement("tr")
            for label in ["Method", "URL", "Status", "Duration (ms)", "Response"] {
                let th = JSHelper.createElement("th")
                JSHelper.setText(th, label)
                JSHelper.append(th, to: headerRow)
            }
            JSHelper.append(headerRow, to: thead)
            JSHelper.append(thead, to: table)

            guard let container = JSHelper.byID(containerID) else {
                fatalError("ReedPipe: container element #\(containerID) not found — is index.html missing it?")
            }
            JSHelper.append(table, to: container)
        }

        // Get or create tbody
        let tbody: JSObject
        if let existingTbody = JSHelper.querySelector(in: table, selector: "tbody") {
            tbody = existingTbody
        } else {
            tbody = JSHelper.createElement("tbody")
            JSHelper.append(tbody, to: table)
        }
        self.tableBody = tbody
    }

    func appendRow(for frame: TrafficFrame) {
        let row = JSHelper.createElement("tr")
        JSHelper.setID(row, "reedpipe-frame-\(frame.id)")
        populate(row: row, with: frame)
        JSHelper.append(row, to: tableBody)
    }

    func updateRow(for frame: TrafficFrame) {
        guard let existingRow = JSHelper.byID("reedpipe-frame-\(frame.id)") else {
            // Shouldn't normally happen (SessionStore only calls this for ids
            // it already appended a row for), but fall back to appending
            // rather than silently dropping the update.
            appendRow(for: frame)
            return
        }
        while let firstChild = JSHelper.firstChild(of: existingRow) {
            JSHelper.remove(firstChild, from: existingRow)
        }
        populate(row: existingRow, with: frame)
    }

    private func populate(row: JSObject, with frame: TrafficFrame) {
        addCell(to: row, text: frame.request.method)
        addCell(to: row, text: frame.request.url)
        addCell(to: row, text: statusText(for: frame))
        addCell(to: row, text: durationText(for: frame))
        addResponseCell(to: row, response: frame.response)
    }

    private func addCell(to row: JSObject, text: String) {
        let cell = JSHelper.createElement("td")
        JSHelper.setText(cell, text)
        JSHelper.append(cell, to: row)
    }

    private func addResponseCell(to row: JSObject, response: CapturedResponse?) {
        let cell: JSObject = JSHelper.createElement("td")
        guard let response: CapturedResponse else {
            JSHelper.setText(cell, "Unavailable")
            JSHelper.append(cell, to: row)
            return
        }

        let button: JSObject = JSHelper.createElement("button")
        button.type = .string("button")
        button.className = .string("reedpipe-view-response")
        JSHelper.setText(button, "View")
        button.onclick = .object(JSClosure { [weak self] _ in
            self?.responseDialog.show(response: response)
            return .undefined
        })
        JSHelper.append(button, to: cell)
        JSHelper.append(cell, to: row)
    }

    private func statusText(for frame: TrafficFrame) -> String {
        if let error = frame.error {
            return "Error: \(error)"
        }
        if let response = frame.response {
            return "\(response.statusCode) \(response.reason)"
        }
        return "…"
    }

    private func durationText(for frame: TrafficFrame) -> String {
        guard let ms = frame.durationMs else { return "—" }
        let tenths = Int((ms * 10).rounded())
        return "\(tenths / 10).\(abs(tenths % 10))"
    }
}
