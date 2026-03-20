const std = @import("std");

const Parser = @import("../../osc.zig").Parser;
const osc = @import("../../osc.zig");

pub const Command = extern struct {
    operation: Operation,
    kind: Kind,

    pub const Operation = enum(c_int) {
        set,
        emit,
        clear,
    };

    pub const Kind = enum(c_int) {
        agent_needs_input,
        agent_plan_ready,
        agent_done,
    };
};

pub fn parse(parser: *Parser, _: ?u8) ?*osc.Command {
    const writer = parser.writer orelse {
        parser.state = .invalid;
        return null;
    };

    const data = writer.buffered();
    var iter = std.mem.tokenizeScalar(u8, data, ';');
    const prefix = iter.next() orelse return invalid(parser);
    if (!std.mem.eql(u8, prefix, "ghostty-attention")) return invalid(parser);

    var version: ?[]const u8 = null;
    var operation: ?Command.Operation = null;
    var kind: ?Command.Kind = null;

    while (iter.next()) |part| {
        var kv = std.mem.splitScalar(u8, part, '=');
        const key = kv.next() orelse continue;
        const value = kv.next() orelse continue;
        if (kv.next() != null) continue;

        if (std.mem.eql(u8, key, "v")) {
            version = value;
        } else if (std.mem.eql(u8, key, "op")) {
            operation = parseOperation(value);
        } else if (std.mem.eql(u8, key, "kind")) {
            kind = parseKind(value);
        }
    }

    if (version == null or !std.mem.eql(u8, version.?, "1")) return invalid(parser);
    if (operation == null or kind == null) return invalid(parser);

    parser.command = .{
        .ghostty_attention = .{
            .operation = operation.?,
            .kind = kind.?,
        },
    };
    return &parser.command;
}

fn parseOperation(value: []const u8) ?Command.Operation {
    if (std.mem.eql(u8, value, "set")) return .set;
    if (std.mem.eql(u8, value, "emit")) return .emit;
    if (std.mem.eql(u8, value, "clear")) return .clear;
    return null;
}

fn parseKind(value: []const u8) ?Command.Kind {
    if (std.mem.eql(u8, value, "agent-needs-input")) return .agent_needs_input;
    if (std.mem.eql(u8, value, "agent-plan-ready")) return .agent_plan_ready;
    if (std.mem.eql(u8, value, "agent-done")) return .agent_done;
    return null;
}

fn invalid(parser: *Parser) ?*osc.Command {
    parser.state = .invalid;
    return null;
}

test "OSC 99 ghostty attention parses set" {
    var parser = Parser.init(std.testing.allocator);
    defer parser.deinit();

    for ("99;ghostty-attention;v=1;op=set;kind=agent-needs-input") |c| {
        parser.next(c);
    }

    const cmd = parser.end(0x07) orelse return error.TestUnexpectedResult;
    try std.testing.expect(cmd.* == .ghostty_attention);
    try std.testing.expectEqual(Command.Operation.set, cmd.ghostty_attention.operation);
    try std.testing.expectEqual(Command.Kind.agent_needs_input, cmd.ghostty_attention.kind);
}

test "OSC 99 ghostty attention parses emit" {
    var parser = Parser.init(std.testing.allocator);
    defer parser.deinit();

    for ("99;ghostty-attention;v=1;op=emit;kind=agent-plan-ready") |c| {
        parser.next(c);
    }

    const cmd = parser.end(0x07) orelse return error.TestUnexpectedResult;
    try std.testing.expect(cmd.* == .ghostty_attention);
    try std.testing.expectEqual(Command.Operation.emit, cmd.ghostty_attention.operation);
    try std.testing.expectEqual(Command.Kind.agent_plan_ready, cmd.ghostty_attention.kind);
}

test "OSC 99 ghostty attention rejects invalid payload" {
    var parser = Parser.init(std.testing.allocator);
    defer parser.deinit();

    for ("99;ghostty-attention;op=emit;kind=agent-plan-ready") |c| {
        parser.next(c);
    }

    try std.testing.expect(parser.end(0x07) == null);
}
