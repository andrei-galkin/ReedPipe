import JavaScriptKit
import Core

final class ResponseDialog {
    private let dialog: JSObject
    private let content: JSObject
    private let encodingNote: JSObject

    init() {
        let dialog: JSObject = JSHelper.createElement("dialog")
        JSHelper.setID(dialog, "reedpipe-response-dialog")
        dialog.className = .string("reedpipe-response-dialog")

        let title: JSObject = JSHelper.createElement("h2")
        JSHelper.setText(title, "Raw HTTP response")
        JSHelper.append(title, to: dialog)

        let encodingNote: JSObject = JSHelper.createElement("p")
        encodingNote.className = .string("reedpipe-response-encoding-note")
        JSHelper.setText(encodingNote, "The binary response body is displayed as Base64.")
        JSHelper.append(encodingNote, to: dialog)

        let content: JSObject = JSHelper.createElement("pre")
        content.className = .string("reedpipe-response-content")
        JSHelper.append(content, to: dialog)

        let closeForm: JSObject = JSHelper.createElement("form")
        closeForm.method = .string("dialog")
        closeForm.className = .string("reedpipe-response-actions")

        let closeButton: JSObject = JSHelper.createElement("button")
        closeButton.type = .string("submit")
        JSHelper.setText(closeButton, "OK")
        JSHelper.append(closeButton, to: closeForm)
        JSHelper.append(closeForm, to: dialog)
        JSHelper.append(dialog, to: JSHelper.body)

        self.dialog = dialog
        self.content = content
        self.encodingNote = encodingNote
    }

    func show(response: CapturedResponse) {
        JSHelper.setText(self.content, RawResponseFormatter.format(response))
        self.encodingNote.hidden = .boolean(!response.bodyIsBase64)
        _ = self.dialog.showModal!()
    }
}
