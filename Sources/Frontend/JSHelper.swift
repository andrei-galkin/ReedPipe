import JavaScriptKit

/// Centralizes the JavaScriptKit call patterns this app relies on.
///
/// Why this file exists: JSObject's dynamic-member *method* calls
/// (`document.createElement("div")`-style) actually go through an Optional
/// closure-returning subscript under the hood, so the correct form per
/// JSObject's own doc comments is `document.createElement!("div")` — with a
/// trailing `!`. Property *reads/writes* (`.innerText`, `.onmessage = ...`)
/// don't need it. This distinction is easy to get subtly wrong, so it's
/// isolated here rather than repeated across every file — if a specific call
/// needs adjusting for your exact JavaScriptKit version, this is the one
/// place to fix it.
enum JSHelper {
    static var document: JSObject {
        JSObject.global.document.object!
    }

    static var body: JSObject {
        document.body.object!
    }

    static func createElement(_ tag: String) -> JSObject {
        document.createElement!(tag).object!
    }

    static func byID(_ id: String) -> JSObject? {
        document.getElementById!(id).object
    }

    static func querySelector(in element: JSObject, selector: String) -> JSObject? {
        element.querySelector!(selector).object
    }

    @discardableResult
    static func append(_ child: JSObject, to parent: JSObject) -> JSValue {
        parent.appendChild!(child)
    }

    @discardableResult
    static func remove(_ child: JSObject, from parent: JSObject) -> JSValue {
        parent.removeChild!(child)
    }

    static func firstChild(of element: JSObject) -> JSObject? {
        element.firstChild.object
    }

    static func setText(_ element: JSObject, _ text: String) {
        element.innerText = .string(text)
    }

    static func setTextColor(_ element: JSObject, _ color: String) {
        guard let style: JSObject = element.style.object else { return }
        style.color = .string(color)
    }

    static func setID(_ element: JSObject, _ id: String) {
        element.id = .string(id)
    }

    /// Constructs `new WebSocket(url)`. Returns nil if the WebSocket API
    /// isn't available in this environment (shouldn't happen in a real
    /// browser, but this is cheaper than crashing if it ever does).
    static func newWebSocket(_ url: String) -> JSObject? {
        guard let constructor = JSObject.global.WebSocket.function else {
            return nil
        }
        return constructor.new(url)
    }

    /// Extracts the text payload from a WebSocket `message` event, given the
    /// arguments array a JSClosure receives.
    static func messageText(from arguments: [JSValue]) -> String? {
        guard let event = arguments.first?.object else { return nil }
        return event.data.string
    }
}
