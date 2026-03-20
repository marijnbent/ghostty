import Testing
@testable import Ghostty

@Suite
struct WorkspaceRemoteSessionKindTests {
    @Test(arguments: [
        ("ssh prod", WorkspaceRemoteSessionKind.ssh),
        ("/usr/bin/ssh prod", WorkspaceRemoteSessionKind.ssh),
        ("sudo ssh prod", WorkspaceRemoteSessionKind.ssh),
        ("env FOO=1 TERM=xterm-256color ssh prod", WorkspaceRemoteSessionKind.ssh),
        ("mosh prod", WorkspaceRemoteSessionKind.mosh),
        ("sudo -- mosh prod", WorkspaceRemoteSessionKind.mosh),
        ("claude", WorkspaceRemoteSessionKind.claude),
        ("cl", WorkspaceRemoteSessionKind.claude),
        ("env FOO=1 TERM=xterm-256color claude", WorkspaceRemoteSessionKind.claude),
        ("sudo -- cl --dangerously-skip-permissions", WorkspaceRemoteSessionKind.claude),
        ("codex chat", WorkspaceRemoteSessionKind.codex),
        ("co chat", WorkspaceRemoteSessionKind.codex),
        ("c chat", WorkspaceRemoteSessionKind.codex),
        ("sudo -- codex chat", WorkspaceRemoteSessionKind.codex),
        ("/opt/homebrew/bin/opencode .", WorkspaceRemoteSessionKind.opencode),
    ])
    func detectsRemoteCommands(
        title: String,
        expected: WorkspaceRemoteSessionKind
    ) {
        #expect(WorkspaceRemoteSessionKind.detect(in: title) == expected)
    }

    @Test(arguments: [
        "",
        "/Users/marijn/Projects/ghostty",
        "vim WorkspaceSidebarView.swift",
        "sudo -k",
        "env FOO=1 BAR=2",
    ])
    func ignoresNonRemoteCommands(title: String) {
        #expect(WorkspaceRemoteSessionKind.detect(in: title) == nil)
    }

    @Test(arguments: [
        ("ssh root@192.168.1.10", WorkspaceRemoteSession(kind: .ssh, target: "root@192.168.1.10")),
        ("ssh -p 2222 prod", WorkspaceRemoteSession(kind: .ssh, target: "prod")),
        ("ssh -l root 192.168.1.10", WorkspaceRemoteSession(kind: .ssh, target: "root@192.168.1.10")),
        ("ssh -o User=root 192.168.1.10", WorkspaceRemoteSession(kind: .ssh, target: "root@192.168.1.10")),
        ("sudo -- mosh devbox", WorkspaceRemoteSession(kind: .mosh, target: "devbox")),
        ("claude --resume", WorkspaceRemoteSession(kind: .claude, target: nil)),
        ("cl --dangerously-skip-permissions", WorkspaceRemoteSession(kind: .claude, target: nil)),
        ("codex chat", WorkspaceRemoteSession(kind: .codex, target: nil)),
        ("co chat", WorkspaceRemoteSession(kind: .codex, target: nil)),
        ("c chat", WorkspaceRemoteSession(kind: .codex, target: nil)),
        ("opencode .", WorkspaceRemoteSession(kind: .opencode, target: nil)),
    ])
    func capturesRemoteTarget(
        title: String,
        expected: WorkspaceRemoteSession
    ) {
        #expect(WorkspaceRemoteSession.detect(in: title) == expected)
    }

    @Test
    func usesIconsOnlyForClaudeAndCodex() {
        #expect(WorkspaceRemoteSessionKind.claude.usesSidebarIcon)
        #expect(WorkspaceRemoteSessionKind.codex.usesSidebarIcon)
        #expect(!WorkspaceRemoteSessionKind.ssh.usesSidebarIcon)
        #expect(!WorkspaceRemoteSessionKind.mosh.usesSidebarIcon)
        #expect(!WorkspaceRemoteSessionKind.opencode.usesSidebarIcon)
    }
}
