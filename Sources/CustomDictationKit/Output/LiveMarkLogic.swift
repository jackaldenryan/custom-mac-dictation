import Foundation

public enum LiveMarkLogic {
    public static func caretStillInMark(caret: Int, markStart: Int) -> Bool {
        caret == markStart
    }
}
