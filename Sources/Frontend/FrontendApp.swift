import JavaScriptKit
import Core

@main
struct FrontendApp {
    static func main() {
        let status = JSHelper.createElement("div")
        JSHelper.setID(status, "reedpipe-status")
        JSHelper.setText(status, "Connecting…")
        JSHelper.append(status, to: JSHelper.body)

        let container = JSHelper.createElement("div")
        JSHelper.setID(container, "reedpipe-sessions")
        JSHelper.append(container, to: JSHelper.body)

        let controller = SessionController(statusElementID: "reedpipe-status", containerID: "reedpipe-sessions")
        controller.start()

        // main() returns immediately, but the page keeps running (event
        // loop, open WebSocket). Nothing else holds a strong reference to
        // `controller` once we're out of this scope, so without this it'd
        // be deallocated — tearing down the WebSocket — right after startup.
        AppRetain.controller = controller
    }
}

enum AppRetain {
    static var controller: SessionController?
}