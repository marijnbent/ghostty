import SwiftUI
import GhosttyKit

extension Ghostty {
    struct Action {}
}

extension Ghostty.Action {
    struct CommandFinished {
        let exitCode: Int?
        let duration: Duration

        var succeeded: Bool? {
            guard let exitCode else { return nil }
            return exitCode == 0
        }
    }

    struct ColorChange {
        let kind: Kind
        let color: Color

        enum Kind {
            case foreground
            case background
            case cursor
            case palette(index: UInt8)
        }

        init(c: ghostty_action_color_change_s) {
            switch c.kind {
            case GHOSTTY_ACTION_COLOR_KIND_FOREGROUND:
                self.kind = .foreground
            case GHOSTTY_ACTION_COLOR_KIND_BACKGROUND:
                self.kind = .background
            case GHOSTTY_ACTION_COLOR_KIND_CURSOR:
                self.kind = .cursor
            default:
                self.kind = .palette(index: UInt8(c.kind.rawValue))
            }

            self.color = Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
        }
    }

    struct MoveTab {
        let amount: Int

        init(c: ghostty_action_move_tab_s) {
            self.amount = c.amount
        }
    }

    struct OpenURL {
        enum Kind {
            case unknown
            case text
            case html

            init(_ c: ghostty_action_open_url_kind_e) {
                switch c {
                case GHOSTTY_ACTION_OPEN_URL_KIND_TEXT:
                    self = .text
                case GHOSTTY_ACTION_OPEN_URL_KIND_HTML:
                    self = .html
                default:
                    self = .unknown
                }
            }
        }

        let kind: Kind
        let url: String

        init(c: ghostty_action_open_url_s) {
            self.kind = Kind(c.kind)

            if let urlCString = c.url {
                let data = Data(bytes: urlCString, count: Int(c.len))
                self.url = String(data: data, encoding: .utf8) ?? ""
            } else {
                self.url = ""
            }
        }
    }

    struct ProgressReport {
        enum State {
            case remove
            case set
            case error
            case indeterminate
            case pause

            init(_ c: ghostty_action_progress_report_state_e) {
                switch c {
                case GHOSTTY_PROGRESS_STATE_REMOVE:
                    self = .remove
                case GHOSTTY_PROGRESS_STATE_SET:
                    self = .set
                case GHOSTTY_PROGRESS_STATE_ERROR:
                    self = .error
                case GHOSTTY_PROGRESS_STATE_INDETERMINATE:
                    self = .indeterminate
                case GHOSTTY_PROGRESS_STATE_PAUSE:
                    self = .pause
                default:
                    self = .remove
                }
            }
        }

        let state: State
        let progress: UInt8?
    }

    struct AgentAttention {
        enum Operation {
            case set
            case emit
            case clear

            init?(_ c: ghostty_action_agent_attention_operation_e) {
                switch c {
                case GHOSTTY_AGENT_ATTENTION_SET:
                    self = .set
                case GHOSTTY_AGENT_ATTENTION_EMIT:
                    self = .emit
                case GHOSTTY_AGENT_ATTENTION_CLEAR:
                    self = .clear
                default:
                    return nil
                }
            }
        }

        enum Kind: Comparable {
            case agentNeedsInput
            case agentPlanReady
            case agentDone

            init?(_ c: ghostty_action_agent_attention_kind_e) {
                switch c {
                case GHOSTTY_AGENT_ATTENTION_AGENT_NEEDS_INPUT:
                    self = .agentNeedsInput
                case GHOSTTY_AGENT_ATTENTION_AGENT_PLAN_READY:
                    self = .agentPlanReady
                case GHOSTTY_AGENT_ATTENTION_AGENT_DONE:
                    self = .agentDone
                default:
                    return nil
                }
            }

            private var priority: Int {
                switch self {
                case .agentNeedsInput:
                    3
                case .agentPlanReady:
                    2
                case .agentDone:
                    1
                }
            }

            static func < (lhs: Self, rhs: Self) -> Bool {
                lhs.priority < rhs.priority
            }
        }

        let operation: Operation
        let kind: Kind
    }

    struct Scrollbar {
        let total: UInt64
        let offset: UInt64
        let len: UInt64

        init(c: ghostty_action_scrollbar_s) {
            total = c.total
            offset = c.offset
            len = c.len
        }
    }

    struct StartSearch {
        let needle: String?

        init(c: ghostty_action_start_search_s) {
            if let needleCString = c.needle {
                self.needle = String(cString: needleCString)
            } else {
                self.needle = nil
            }
        }
    }

    enum PromptTitle {
        case surface
        case tab

        init(_ c: ghostty_action_prompt_title_e) {
            switch c {
            case GHOSTTY_PROMPT_TITLE_TAB:
                self = .tab
            default:
                self = .surface
            }
        }
    }

    enum KeyTable {
        case activate(name: String)
        case deactivate
        case deactivateAll

        init?(c: ghostty_action_key_table_s) {
            switch c.tag {
            case GHOSTTY_KEY_TABLE_ACTIVATE:
                let data = Data(bytes: c.value.activate.name, count: c.value.activate.len)
                let name = String(data: data, encoding: .utf8) ?? ""
                self = .activate(name: name)
            case GHOSTTY_KEY_TABLE_DEACTIVATE:
                self = .deactivate
            case GHOSTTY_KEY_TABLE_DEACTIVATE_ALL:
                self = .deactivateAll
            default:
                return nil
            }
        }
    }
}

// Putting the initializer in an extension preserves the automatic one.
extension Ghostty.Action.ProgressReport {
    init(c: ghostty_action_progress_report_s) {
        self.state = State(c.state)
        self.progress = c.progress >= 0 ? UInt8(c.progress) : nil
    }
}

extension Ghostty.Action.CommandFinished {
    init(c: ghostty_action_command_finished_s) {
        self.exitCode = c.exit_code >= 0 ? Int(c.exit_code) : nil
        self.duration = .nanoseconds(c.duration)
    }
}

extension Ghostty.Action.AgentAttention {
    init?(c: ghostty_action_agent_attention_s) {
        guard let operation = Operation(c.operation), let kind = Kind(c.kind) else { return nil }
        self.operation = operation
        self.kind = kind
    }
}
