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
}
