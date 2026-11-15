#if os(iOS)
  import EscriboCore
  import Foundation
  import Testing
  import UIKit

  @testable import SwiftEscribo

  /// The iOS external reset writes the storage directly instead of going through UIKit's
  /// keyboard path (``EscriboTextView/replaceDocumentOutsideKeyboardPath(with:)``), and keeps
  /// by hand what that path used to give: one undo action, its redo, and one change
  /// notification.
  @MainActor
  @Suite("iOS external reset stays off the keyboard path")
  struct IOSExternalResetTests {

    /// Closes UIKit's per-event undo group, so an undo registration becomes undoable.
    private func settle() {
      _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, false)
    }

    /// An editor in a window, so its text view has an undo manager.
    @MainActor
    private final class Hosted {
      let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
      let editor = EscriboTextView(language: .fountain, theme: .fountainLight)
      let counter = ChangeCounter()

      init() {
        let controller = UIViewController()
        controller.view.addSubview(editor.textView)
        editor.textView.frame = controller.view.bounds
        window.rootViewController = controller
        window.isHidden = false
        editor.textView.delegate = counter
      }

      var undo: UndoManager? { editor.textView.undoManager }
    }

    @MainActor
    private final class ChangeCounter: NSObject, UITextViewDelegate {
      var count = 0
      func textViewDidChange(_ textView: UITextView) { count += 1 }
    }

    /// The keyboard path registers an undo action for every replacement, the first load
    /// included, so Undo right after opening a file emptied it. This reads `false` only when
    /// the reset stays off that path.
    @Test("Loading into an empty editor registers no undo action")
    func firstLoadIsNotUndoable() throws {
      let hosted = Hosted()
      let undo = try #require(hosted.undo)
      undo.removeAllActions()

      #expect(hosted.editor.applyExternalText("INT. ROOM - DAY\n\nA screenplay.\n") == true)
      settle()

      #expect(undo.canUndo == false)
      #expect(hosted.editor.currentText == "INT. ROOM - DAY\n\nA screenplay.\n")
    }

    @Test("A later reset is one undo action, and its undo has a redo")
    func laterResetUndoesAndRedoes() throws {
      let hosted = Hosted()
      let undo = try #require(hosted.undo)
      hosted.editor.applyExternalText("first draft\n")
      settle()
      undo.removeAllActions()
      hosted.counter.count = 0

      #expect(hosted.editor.applyExternalText("second draft\n") == true)
      settle()
      #expect(hosted.counter.count == 1)
      #expect(undo.canUndo == true)

      undo.undo()
      settle()
      #expect(hosted.editor.currentText == "first draft\n")
      #expect(undo.canUndo == false)
      // The undo reached the delegate too, which is how the host's binding hears of it.
      #expect(hosted.counter.count == 2)

      #expect(undo.canRedo == true)
      undo.redo()
      settle()
      #expect(hosted.editor.currentText == "second draft\n")
    }

    /// A feature-length document loads while the text view is first responder, the state
    /// in which UIKit's keyboard path runs its text analysis.
    ///
    /// No timing assertion: timing tests never run in CI (a loaded runner took 2.9 s here).
    /// The simulator does not reproduce the device's keyboard-path cost anyway.
    @Test("A feature-length reset into a focused editor lands whole")
    func featureLengthResetWhileFocused() throws {
      let hosted = Hosted()
      _ = hosted.editor.textView.becomeFirstResponder()
      let scene = String(
        repeating: "INT. KITCHEN - NIGHT\n\nMARA pours coffee. \"Don't.\"\n\nMARA\nWe're late.\n\n",
        count: 2_000)

      #expect(hosted.editor.applyExternalText(scene) == true)
      #expect(hosted.editor.currentText == scene)
    }
  }
#endif
