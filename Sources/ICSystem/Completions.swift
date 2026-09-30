/// Static shell completions for `iclean`.
public enum Completions {
    static let commands = ["status", "why", "explain", "thaw", "freeze", "undo", "mode", "profile", "stats", "advise",
                           "quarantine", "habits", "workspace", "simulate", "trace", "config", "doctor", "install",
                           "uninstall", "bench", "completions", "version", "help"]
    static let sub: [String: [String]] = [
        "mode": ["observe", "active"], "profile": ["work", "batterySaver", "presentation", "dev", "auto"],
        "habits": ["show", "reset", "export"], "quarantine": ["release"], "trace": ["export"],
        "config": ["path", "show", "validate", "allow", "deny", "import", "export"], "thaw": ["--all"],
        "completions": ["zsh", "bash", "fish"], "doctor": ["--report"], "uninstall": ["--purge"],
    ]

    public static func script(for shell: String) -> String {
        let all = commands.joined(separator: " ")
        switch shell {
        case "bash":
            let cases = sub.sorted { $0.key < $1.key }.map { "    \($0.key)) COMPREPLY=($(compgen -W \"\($0.value.joined(separator: " "))\" -- \"$cur\")) ;;" }
            return """
            _iclean() {
              local cur="${COMP_WORDS[COMP_CWORD]}"
              if [ "$COMP_CWORD" -eq 1 ]; then COMPREPLY=($(compgen -W "\(all)" -- "$cur")); return; fi
              case "${COMP_WORDS[1]}" in
            \(cases.joined(separator: "\n"))
              esac
            }
            complete -F _iclean iclean
            """
        case "fish":
            var l = ["complete -c iclean -f -n '__fish_use_subcommand' -a '\(all)'"]
            for (c, s) in sub.sorted(by: { $0.key < $1.key }) {
                l.append("complete -c iclean -f -n '__fish_seen_subcommand_from \(c)' -a '\(s.joined(separator: " "))'")
            }
            return l.joined(separator: "\n")
        default:
            let cases = sub.sorted { $0.key < $1.key }.map { "    \($0.key)) compadd \($0.value.joined(separator: " ")) ;;" }
            return """
            #compdef iclean
            _iclean() {
              if (( CURRENT == 2 )); then compadd \(all); return; fi
              case $words[2] in
            \(cases.joined(separator: "\n"))
              esac
            }
            _iclean "$@"
            """
        }
    }
}
