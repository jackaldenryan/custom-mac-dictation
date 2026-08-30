import Foundation
import JavaScriptCore

public struct PostProcessConfig: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var script: String

    public init(id: String, name: String, script: String) {
        self.id = id
        self.name = name
        self.script = script
    }

    public var isBuiltInDefault: Bool { id == PostProcessConfig.defaultID }

    public static let defaultID = "default"

    public static var builtInDefault: PostProcessConfig {
        PostProcessConfig(id: defaultID, name: "Default", script: DefaultPostProcess.javascriptSource)
    }
}

public struct PostProcessInput: Equatable, Sendable {
    public var text: String
    public var isPartial: Bool
    public var pendingLeadSpace: Bool
    public var lastTypedAge: Double
    public var lonePunctuationDelay: Double
    public var isLonePunctuation: Bool
    public var midSentence: Bool
    public var snapshot: CaretSnapshot?

    public init(
        text: String,
        isPartial: Bool,
        pendingLeadSpace: Bool,
        lastTypedAge: Double,
        lonePunctuationDelay: Double,
        isLonePunctuation: Bool,
        midSentence: Bool,
        snapshot: CaretSnapshot?
    ) {
        self.text = text
        self.isPartial = isPartial
        self.pendingLeadSpace = pendingLeadSpace
        self.lastTypedAge = lastTypedAge
        self.lonePunctuationDelay = lonePunctuationDelay
        self.isLonePunctuation = isLonePunctuation
        self.midSentence = midSentence
        self.snapshot = snapshot
    }
}

public enum DefaultPostProcess {
    public static func apply(_ input: PostProcessInput) -> String? {
        if input.isLonePunctuation {
            if input.lastTypedAge < input.lonePunctuationDelay { return nil }
            return input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var body = input.text
        if isMidSentence(input) {
            body = SentenceFit.midSentence(input.text)
        }
        guard !body.isEmpty else { return body }
        if FieldFit.needsLeadSpace(body, snapshot: input.snapshot, pendingLeadSpace: input.pendingLeadSpace) {
            return " " + body
        }
        return body
    }

    static func isMidSentence(_ input: PostProcessInput) -> Bool {
        guard let snap = input.snapshot else { return input.midSentence }
        if snap.atStart { return false }
        if let before = snap.before, before == "\n" || before == "\r" { return false }
        guard let ch = snap.lastNonSpaceBefore else { return input.midSentence }
        if ".?!…".contains(ch) { return false }
        if "•·●-*".contains(ch) { return false }
        return true
    }

    public static let javascriptSource = """
    function process(ctx) {
      var text = ctx.text || "";
      if (ctx.isLonePunctuation) {
        if (ctx.lastTypedAge < ctx.lonePunctuationDelay) return null;
        return String(text).trim();
      }
      var body = text;
      if (isMidSentence(ctx)) body = midSentence(body);
      if (!body) return body;
      if (needsLeadSpace(body, ctx)) return " " + body;
      return body;
    }

    function isMidSentence(ctx) {
      var snap = ctx.caret;
      if (!snap) return !!ctx.midSentence;
      if (snap.atStart) return false;
      var before = snap.before || "";
      if (before === "\\n" || before === "\\r") return false;
      var ch = snap.lastNonSpaceBefore;
      if (!ch) return !!ctx.midSentence;
      if (".?!…".indexOf(ch) >= 0) return false;
      if ("•·●-*".indexOf(ch) >= 0) return false;
      return true;
    }

    function midSentence(text) {
      var t = String(text).replace(/^\\s+|\\s+$/g, "");
      if (!t) return text;
      if (t.length > 3 && t.slice(-3) === "...") t = t.slice(0, -3).replace(/\\s+$/g, "");
      else if (t.slice(-1) === "." && t.slice(-2) !== "..") t = t.slice(0, -1).replace(/\\s+$/g, "");
      else if (t.slice(-1) === "?" && t.length >= 2 && /[A-Za-z0-9]/.test(t.charAt(t.length - 2))) t = t.slice(0, -1).replace(/\\s+$/g, "");
      return decapitalizeIfNeeded(t);
    }

    function decapitalizeIfNeeded(text) {
      if (!text) return text;
      var first = text.charAt(0);
      if (first !== first.toUpperCase()) return text;
      var rest = text.slice(1);
      if (first === "I" && (rest === "" || rest.charAt(0) === "'" || rest.charAt(0) === "’" || rest.charAt(0) === " ")) return text;
      if (rest && rest.charAt(0) === rest.charAt(0).toUpperCase() && rest.charAt(0) !== rest.charAt(0).toLowerCase()) return text;
      return first.toLowerCase() + rest;
    }

    function needsLeadSpace(body, ctx) {
      if (!body || /\\s/.test(body.charAt(0))) return false;
      if (",.!?:;)]}'\\"”’/".indexOf(body.charAt(0)) >= 0) return false;
      var snap = ctx.caret;
      if (snap) {
        if (snap.selectedLength > 0) return false;
        if (snap.atStart) return false;
        var before = snap.before || "";
        if (!before) return false;
        if (/\\s/.test(before)) return false;
        if ("([{\\"'“‘".indexOf(before) >= 0) return false;
        if (".?!…".indexOf(before) >= 0) return true;
        if (/[A-Za-z0-9]/.test(before) || before === "'" || before === "’") return true;
        return false;
      }
      return !!ctx.pendingLeadSpace;
    }
    """
}

public enum PostProcessor {
    nonisolated(unsafe) private static var cachedScript: String?
    nonisolated(unsafe) private static var cachedContext: JSContext?
    nonisolated(unsafe) public static var lastError = ""

    public static func process(_ input: PostProcessInput, settings: AppSettings) -> String? {
        let config = settings.activePostProcessConfig
        if config.isBuiltInDefault {
            lastError = ""
            return DefaultPostProcess.apply(input)
        }
        do {
            return try runJavaScript(config.script, input: input)
        } catch {
            lastError = error.localizedDescription
            DiagnosticLog.line("Post-process JS failed: \(error.localizedDescription)")
            return DefaultPostProcess.apply(input)
        }
    }

    public static func runJavaScript(_ script: String, input: PostProcessInput) throws -> String? {
        let context: JSContext
        if cachedScript == script, let cachedContext {
            context = cachedContext
        } else {
            guard let created = JSContext() else {
                throw NSError(domain: "PostProcess", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create a JavaScript context."])
            }
            created.exceptionHandler = { _, exception in
                if let exception {
                    lastError = exception.toString() ?? "JavaScript error"
                }
            }
            created.evaluateScript(script)
            if let exception = created.exception {
                throw NSError(domain: "PostProcess", code: 2, userInfo: [NSLocalizedDescriptionKey: exception.toString() ?? "JavaScript error"])
            }
            cachedScript = script
            cachedContext = created
            context = created
        }
        guard let fn = context.objectForKeyedSubscript("process"), fn.isObject else {
            throw NSError(domain: "PostProcess", code: 3, userInfo: [NSLocalizedDescriptionKey: "Script must define function process(ctx)."])
        }
        lastError = ""
        let result = fn.call(withArguments: [jsObject(input, in: context)])
        if let exception = context.exception {
            context.exception = nil
            throw NSError(domain: "PostProcess", code: 4, userInfo: [NSLocalizedDescriptionKey: exception.toString() ?? "JavaScript error"])
        }
        if result == nil || result?.isUndefined == true || result?.isNull == true {
            return nil
        }
        return result?.toString()
    }

    private static func jsObject(_ input: PostProcessInput, in context: JSContext) -> JSValue {
        var caret: [String: Any] = [:]
        if let snap = input.snapshot {
            caret["before"] = snap.before.map(String.init) ?? NSNull()
            caret["lastNonSpaceBefore"] = snap.lastNonSpaceBefore.map(String.init) ?? NSNull()
            caret["after"] = snap.after.map(String.init) ?? NSNull()
            caret["selectedLength"] = snap.selectedLength
            caret["atStart"] = snap.atStart
        }
        let object: [String: Any] = [
            "text": input.text,
            "isPartial": input.isPartial,
            "pendingLeadSpace": input.pendingLeadSpace,
            "lastTypedAge": input.lastTypedAge,
            "lonePunctuationDelay": input.lonePunctuationDelay,
            "isLonePunctuation": input.isLonePunctuation,
            "midSentence": input.midSentence,
            "caret": input.snapshot == nil ? NSNull() : caret
        ]
        return JSValue(object: object, in: context)
    }
}
