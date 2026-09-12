import Foundation

/// Turning a user-typed start command into something the runner can own.
///
/// Managed mode has to be able to *terminate* what it started, so how the
/// command is run is chosen for exactly that:
///
/// - A command that parses into plain words (`dsh --profile web --port 0
///   --no-open`, `"/opt/my dsh/dsh" web`) is exec'd directly, word for word.
///   The process the app holds *is* the dsh, and `terminate()` reaches it —
///   the same guarantee the standard managed invocation has always had.
/// - Anything that needs a real shell (`cd ~/x && dsh web`, `dsh web 2>&1 |
///   tee log`) runs through the login shell wrapped in `forwardingWrapper`,
///   which forwards the signals the app sends to the child it actually asked
///   for. A plain `zsh -l -c '<command>'` would not: SIGTERM to the shell
///   kills only the shell and orphans the dsh.
public enum ShellCommand {
    /// Characters that make a command line a shell program rather than a
    /// list of words. `~` and `*?[]{}` are here because direct execution
    /// cannot expand them; `$` and backtick because their result would
    /// differ; `#` because the rest of the line would be a comment.
    ///
    /// Line breaks are *not* here: they are rejected through
    /// `Character.isNewline` instead, because `"\r\n"` is a single Swift
    /// `Character` and would match neither `"\r"` nor `"\n"` in a set.
    static let shellMetacharacters: Set<Character> = [
        ";", "|", "&", "(", ")", "<", ">", "$", "`", "*", "?", "[", "]", "{", "}", "~", "#",
    ]

    /// Split a command line into words the way a shell would, honouring
    /// quotes; `nil` when the line is a shell program this cannot mirror.
    ///
    /// Quoting is the only shell syntax mirrored: single quotes are fully
    /// literal, double quotes literal apart from `\"` and `\\`, and a
    /// backslash makes the next character literal. One level, no surprises —
    /// anything more than that is a shell program and returns `nil`.
    ///
    /// Surrounding whitespace is trimmed before anything else, so a command
    /// that merely ends in a newline is still a plain word list; a line break
    /// *inside* the command is shell syntax and rejected.
    public static func words(_ command: String) -> [String]? {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        var words: [String] = []
        var current = ""
        var hasWord = false
        var index = command.startIndex

        while index < command.endIndex {
            let character = command[index]
            switch character {
            case " ", "\t":
                if hasWord {
                    words.append(current)
                    current = ""
                    hasWord = false
                }
            case "'":
                // Everything to the closing quote is literal. An unterminated
                // quote is a shell's error message, not a word list.
                var closing = command.index(after: index)
                var closed = false
                while closing < command.endIndex {
                    if command[closing] == "'" {
                        closed = true
                        break
                    }
                    current.append(command[closing])
                    closing = command.index(after: closing)
                }
                guard closed else { return nil }
                hasWord = true
                index = closing
            case "\"":
                var closing = command.index(after: index)
                var closed = false
                while closing < command.endIndex {
                    let inside = command[closing]
                    if inside == "\"" {
                        closed = true
                        break
                    }
                    // Inside double quotes a backslash escapes only `"` and
                    // itself — every other backslash is literal, which is why
                    // `"C:\dir"` survives intact. `$` and backticks mean the
                    // shell, and direct execution cannot promise what they
                    // would produce.
                    if inside == "\\",
                       let next = command.index(closing, offsetBy: 1, limitedBy: command.endIndex),
                       next < command.endIndex,
                       command[next] == "\"" || command[next] == "\\" {
                        current.append(command[next])
                        closing = command.index(after: closing)
                    } else if inside == "$" || inside == "`" {
                        return nil
                    } else {
                        current.append(inside)
                    }
                    closing = command.index(after: closing)
                }
                guard closed else { return nil }
                hasWord = true
                index = closing
            case "\\":
                guard let next = command.index(index, offsetBy: 1, limitedBy: command.endIndex), next < command.endIndex
                else { return nil }
                current.append(command[next])
                hasWord = true
                index = next
            default:
                // A line break separates commands, so a line list is a shell
                // program — flattening it into one argv would run something
                // the user never wrote. `isNewline` covers CR, LF and the
                // single `\r\n` grapheme alike.
                if character.isNewline { return nil }
                if shellMetacharacters.contains(character) { return nil }
                current.append(character)
                hasWord = true
            }
            index = command.index(after: index)
        }

        if hasWord { words.append(current) }
        guard !words.isEmpty else { return nil }
        // An environment-assignment prefix (`DSH_HOME=/x dsh web`) is shell
        // syntax too: better the fallback shell than a file literally named
        // "DSH_HOME=/x" that will never be found.
        if isEnvironmentAssignment(words[0]) { return nil }
        return words
    }

    /// Whether `word` is shaped like `NAME=…`, an environment assignment.
    static func isEnvironmentAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        let name = word[word.startIndex..<equals]
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Wrap a shell command so signals sent to the wrapper reach the command.
    ///
    /// The command is backgrounded inside the wrapper's own shell and a trap
    /// forwards TERM/INT/HUP to it before the wrapper gives up. `wait` then
    /// holds the wrapper open for the child's whole life and propagates its
    /// exit status — which is what makes the pair look, from the outside,
    /// exactly like one process.
    ///
    /// The trap signals the **job** (`%%`), not `$!`. For a pipeline — and
    /// `dsh web 2>&1 | tee log` is the very example this wrapper exists for —
    /// `$!` is the *last* element, so signalling it killed the `tee` and left
    /// the dsh running: measured, the child survived the app's own quit and
    /// kept the port. The job covers every member of the pipeline. `$!` stays
    /// as the fallback for a shell whose job control is unavailable, and it
    /// remains what `wait` is given, since that is what carries the exit
    /// status back.
    ///
    /// The command is embedded verbatim: the wrapper is passed to the shell
    /// as one argument, so no quoting of the user's text is needed and none
    /// is done. Only the last line is backgrounded, so a multi-line command's
    /// earlier lines still run as setup in the wrapper's own shell.
    public static func forwardingWrapper(_ command: String) -> String {
        // A trailing `&` would collide with the wrapper's own backgrounding.
        var trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("&") {
            trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed + #" &"#
            + "\n_bezel_child=$!"
            + "\ntrap 'kill -TERM %% 2>/dev/null || kill -TERM \"${_bezel_child}\" 2>/dev/null' TERM INT HUP EXIT"
            + "\nwait \"${_bezel_child}\""
            + "\nexit $?"
    }
}
