// SPDX-License-Identifier: AGPL-3.0-or-later
// Starts (or reuses) `dsh web` on the SSH host. Port of
// 原 Flutter 版 lib/remote/ssh/remote_bootstrap.dart; the scripts are kept identical so
// the Android and iOS apps share one `$HOME/.dsh-app-remote` state directory.
import Foundation

public let defaultDshLaunchCommand = "dsh web"

/// A `dsh web` launch URL (`http://127.0.0.1:<port>/?token=…`).
public struct DshLaunchURL: Sendable, Equatable {
    public let baseURL: URL
    public let token: String

    public static func parse(_ text: String) -> DshLaunchURL? {
        guard let range = text.range(of: #"https?://\S+"#, options: .regularExpression),
              var parts = URLComponents(string: String(text[range])),
              let token = parts.queryItems?.first(where: { $0.name == "token" })?.value, !token.isEmpty else { return nil }
        parts.query = nil; parts.fragment = nil
        if parts.path == "/" { parts.path = "" }
        guard let base = parts.url else { return nil }
        return DshLaunchURL(baseURL: base, token: token)
    }
}

public struct RemoteEndpoint: Sendable {
    public let port: Int
    public let token: String
    public let pid: Int?
    public let reused: Bool
    public let home: String?
}

public struct RemoteBootstrap: Sendable {
    public let launchCommand: String
    public let workingDirectory: String?
    public let startTimeout: Int

    static let tag = "DSHAPP"
    static let stateDir = "$HOME/.dsh-app-remote"

    public init(launchCommand: String = defaultDshLaunchCommand, workingDirectory: String? = nil, startTimeout: Int = 60) {
        let trimmed = launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        self.launchCommand = trimmed.isEmpty ? defaultDshLaunchCommand : trimmed
        self.workingDirectory = workingDirectory
        self.startTimeout = startTimeout
    }

    var usesDefaultCommand: Bool { launchCommand == defaultDshLaunchCommand }

    /// Reuses a running server started by this app with the same command, else starts one.
    public func ensureRunning(on ssh: SSHConnection, forceRestart: Bool = false,
                              progress: (@Sendable (String) -> Void)? = nil) async throws -> RemoteEndpoint {
        if !forceRestart {
            let result = try await ssh.run(probeScript(), timeout: 20)
            if Self.missingShell(result) { throw RemoteError(.noShell, detail: result.stderr) }
            let probe = Self.parseProbe(result.stdout)
            if let pid = probe.pid, probe.sameCommand, let line = probe.url, let url = DshLaunchURL.parse(line),
               let port = url.baseURL.port {
                return RemoteEndpoint(port: port, token: url.token, pid: pid, reused: true, home: probe.home)
            }
        }
        progress?("start")
        let result = try await ssh.run(startScript(), timeout: TimeInterval(startTimeout + 20))
        if Self.missingShell(result) { throw RemoteError(.noShell, detail: result.stderr) }
        return try Self.parseStart(result, customCommand: !usesDefaultCommand)
    }

    public func stop(on ssh: SSHConnection) async {
        _ = try? await ssh.run(prelude() + stopOld + "true\n", timeout: 15)
    }

    // MARK: Scripts (POSIX sh)

    func prelude() -> String {
        """
        umask 077
        D="\(Self.stateDir)"
        _st() {
          if [ -r "/proc/$1/stat" ]; then
            S=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
            S=${S##*) }
            set -- $S
            [ "$#" -ge 20 ] || return 1
            shift 19
            printf '%s\\n' "$1"
          else
            ps -p "$1" -o lstart= 2>/dev/null
          fi
        }
        ours() {
          kill -0 "$1" 2>/dev/null || return 1
          if [ -f "$D/web.st" ]; then
            A=$(_st "$1") || return 1
            B=$(cat "$D/web.st" 2>/dev/null) || return 1
            [ -n "$A" ] && [ -n "$B" ] && [ "$A" = "$B" ]
            return $?
          fi
          A=$(ps -p "$1" -o args= 2>/dev/null) || return 1
          case "$A" in
            *'--host 127.0.0.1 --port 0 --no-open'*) return 0;;
            *) return 1;;
          esac
        }

        """
    }

    func probeScript() -> String {
        let t = Self.tag
        return prelude() + """
        printf '\(t) home %s\\n' "$HOME"
        if [ -f "$D/web.pid" ]; then
          P=$(cat "$D/web.pid" 2>/dev/null)
          if [ -n "$P" ] && ours "$P"; then
            printf '\(t) alive %s\\n' "$P"
            if [ "$(cat "$D/web.cmd" 2>/dev/null)" = \(shQuote(launchCommand)) ]; then printf '\(t) samecmd\\n'; fi
            L=$(grep -E 'https?://[^ ]*[?&]token=' "$D/web.log" 2>/dev/null | tail -n 1)
            printf '\(t) url %s\\n' "$L"
          else
            rm -f "$D/web.pid"
          fi
        fi
        true

        """
    }

    let stopOld = """
    if [ -f "$D/web.pid" ]; then
      P=$(cat "$D/web.pid" 2>/dev/null)
      if [ -n "$P" ] && ours "$P"; then
        if command -v pkill >/dev/null 2>&1; then pkill -TERM -P "$P" 2>/dev/null; fi
        kill "$P" 2>/dev/null
        i=0; while kill -0 "$P" 2>/dev/null && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
        ours "$P" && kill -9 "$P" 2>/dev/null
      fi
      rm -f "$D/web.pid"
    fi

    """

    static let dshSearch = """
    if ! command -v dsh >/dev/null 2>&1; then
      F=""
      for c in "$HOME/.local/bin" "$HOME/.npm-global/bin" "$HOME/.npm/bin" "$HOME/.volta/bin" "$HOME/.bun/bin" \\
               "$HOME/.local/share/pnpm" "$HOME/Library/pnpm" /usr/local/bin /opt/homebrew/bin \\
               "$HOME"/.nvm/versions/node/*/bin "$HOME"/.local/share/fnm/node-versions/*/installation/bin; do
        if [ -x "$c/dsh" ]; then F="$c"; fi
      done
      if [ -n "$F" ]; then PATH="$F:$PATH"; export PATH; fi
    fi
    if ! command -v dsh >/dev/null 2>&1; then printf 'DSHAPP nodsh\\n'; exit 127; fi
    printf 'DSHAPP dsh %s\\n' "$(command -v dsh)"

    """

    func startScript() -> String {
        let t = Self.tag
        let seconds = min(max(startTimeout, 5), 600)
        var s = prelude()
        s += "printf '\(t) home %s\\n' \"$HOME\"\n"
        s += "mkdir -p \"$D\" || { printf '\(t) nodir\\n'; exit 70; }\n"
        s += "chmod 700 \"$D\" 2>/dev/null\n"
        s += stopOld
        if usesDefaultCommand { s += Self.dshSearch }
        if let cwd = workingDirectory?.trimmingCharacters(in: .whitespaces), !cwd.isEmpty {
            s += "cd \(Self.remotePathExpr(cwd)) 2>/dev/null || printf '\(t) nocwd\\n'\n"
        }
        s += """
        printf '%s' \(shQuote(launchCommand)) > "$D/web.cmd"
        : > "$D/web.log"
        NO_COLOR=1; export NO_COLOR
        N=""; if command -v nohup >/dev/null 2>&1; then N=nohup; fi
        $N \(launchCommand) --host 127.0.0.1 --port 0 --no-open </dev/null >>"$D/web.log" 2>&1 &
        P=$!
        _st "$P" > "$D/web.st"
        printf '%s\\n' "$P" > "$D/web.pid"
        printf '\(t) started %s\\n' "$P"
        i=0
        while [ $i -lt \(seconds) ]; do
          L=$(grep -E 'https?://[^ ]*[?&]token=' "$D/web.log" 2>/dev/null | tail -n 1)
          if [ -n "$L" ]; then printf '\(t) url %s\\n' "$L"; exit 0; fi
          if ! kill -0 "$P" 2>/dev/null; then
            printf '\(t) exited\\n'; tail -n 20 "$D/web.log" 2>/dev/null | sed 's/^/\(t) log /'; exit 1
          fi
          sleep 1; i=$((i+1))
        done
        printf '\(t) timeout\\n'; tail -n 20 "$D/web.log" 2>/dev/null | sed 's/^/\(t) log /'; exit 1

        """
        return s
    }

    // MARK: Parsing

    static func tagged(_ stdout: String) -> [(String, String)] {
        stdout.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
            let line = raw.replacingOccurrences(of: "\r", with: "")
            guard line.hasPrefix(tag + " ") else { return nil }
            let rest = line.dropFirst(tag.count + 1)
            guard let space = rest.firstIndex(of: " ") else { return (String(rest), "") }
            return (String(rest[..<space]), String(rest[rest.index(after: space)...]))
        }
    }

    struct Probe { var home: String?; var pid: Int?; var sameCommand = false; var url: String? }

    static func parseProbe(_ stdout: String) -> Probe {
        var probe = Probe()
        for (key, value) in tagged(stdout) {
            switch key {
            case "home": probe.home = value.isEmpty ? nil : value
            case "alive": probe.pid = Int(value.trimmingCharacters(in: .whitespaces))
            case "samecmd": probe.sameCommand = true
            case "url": probe.url = value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value
            default: break
            }
        }
        return probe
    }

    static func parseStart(_ result: ExecResult, customCommand: Bool) throws -> RemoteEndpoint {
        var home: String?, pid: Int?, url: String?
        var noDsh = false, exited = false, timedOut = false
        var log: [String] = []
        for (key, value) in tagged(result.stdout) {
            switch key {
            case "home": home = value.isEmpty ? nil : value
            case "started": pid = Int(value.trimmingCharacters(in: .whitespaces))
            case "url": url = value
            case "nodsh": noDsh = true
            case "exited": exited = true
            case "timeout": timedOut = true
            case "log": log.append(value)
            default: break
            }
        }
        if let url, let parsed = DshLaunchURL.parse(url), let port = parsed.baseURL.port {
            return RemoteEndpoint(port: port, token: parsed.token, pid: pid, reused: false, home: home)
        }
        let tail = redactTokens(log.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n"))
        if noDsh || (exited && tail.range(of: #"command not found|not found|No such file or directory|can.t open|ENOENT"#,
                                          options: [.regularExpression, .caseInsensitive]) != nil) {
            throw RemoteError(.dshNotFound, detail: tail.isEmpty ? nil : tail)
        }
        if timedOut { throw RemoteError(.dshTimeout, detail: tail.isEmpty ? nil : tail) }
        if exited { throw RemoteError(.dshStartFailed, detail: tail.isEmpty ? nil : tail) }
        let stderr = result.stderr.split(separator: "\n").prefix(6).joined(separator: "\n")
        let code = result.exitCode.map { "exit \($0)" }
        throw RemoteError(.dshStartFailed, detail: [code, stderr.isEmpty ? nil : stderr].compactMap { $0 }.joined(separator: "\n"))
    }

    static func missingShell(_ result: ExecResult) -> Bool {
        !result.stdout.contains(tag) && result.stderr.range(
            of: #"'sh' is not recognized|sh: (command )?not found|command not found: sh|No such file or directory.*\bsh\b"#,
            options: .regularExpression) != nil
    }

    public static func redactTokens(_ text: String) -> String {
        text.replacingOccurrences(of: #"token=[A-Za-z0-9._~%-]+"#, with: "token=•••", options: .regularExpression)
    }

    static func remotePathExpr(_ path: String) -> String {
        let p = path.trimmingCharacters(in: .whitespaces)
        if p == "~" { return "\"$HOME\"" }
        if p.hasPrefix("~/") { return "\"$HOME\"/" + shQuote(String(p.dropFirst(2))) }
        return shQuote(p)
    }
}
