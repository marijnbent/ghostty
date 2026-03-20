import Testing
import GhosttyKit
@testable import Ghostty

struct WorkspaceAttentionTests {
    @Test func agentAttentionBridgeDecodesSetNeedsInput() {
        let c = ghostty_action_agent_attention_s(
            operation: GHOSTTY_AGENT_ATTENTION_SET,
            kind: GHOSTTY_AGENT_ATTENTION_AGENT_NEEDS_INPUT
        )

        let attention = Ghostty.Action.AgentAttention(c: c)

        #expect(attention?.operation == .set)
        #expect(attention?.kind == .agentNeedsInput)
    }

    @Test func commandFinishedBridgeDecodesExitCodeAndDuration() {
        let c = ghostty_action_command_finished_s(exit_code: 7, duration: 42)
        let finished = Ghostty.Action.CommandFinished(c: c)

        #expect(finished.exitCode == 7)
        #expect(finished.duration == .nanoseconds(42))
        #expect(finished.succeeded == false)
    }

    @Test func stickyAgentAttentionPrefersNeedsInput() {
        let states: [WorkspaceStickyAgentAttention] = [.done, .needsInput, .planReady]

        #expect(states.max() == .needsInput)
        #expect(WorkspaceStickyAgentAttention(kind: .agentPlanReady).badgeLabel == "PLAN")
    }

    @Test func transientAttentionMapsToSidebarBadges() {
        #expect(
            WorkspaceTransientAttention.agentPlanReady.sidebarBadge ==
                .pill(label: "PLAN", tone: .accent)
        )
        #expect(
            WorkspaceTransientAttention.commandFailure.sidebarBadge ==
                .symbol(systemName: "exclamationmark.circle.fill", tone: .warning)
        )
    }
}
