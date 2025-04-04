const std = @import("std");
const ncur = @cImport(@cInclude("curses.h"));
const loc = @cImport(@cInclude("locale.h"));

fn init_curses() void {
    _ = loc.setlocale(loc.LC_ALL, "");
    _ = ncur.initscr();
    _ = ncur.noecho();
    _ = ncur.cbreak();
    _ = ncur.keypad(ncur.stdscr, true);
}
fn deinit_curses() void {
    _ = ncur.nocbreak();
    _ = ncur.echo();
    _ = ncur.endwin();
}

const Mode = enum {
    Command,
    Insert,
};

const Cursor = struct {
    position: i64,
    count: i64,
};

const Command = union(enum) {
    insert: Insert,
    erase: Erase,

    pub fn inverse(self: Command) Command {
        switch (self) {
            .insert => |i| {
                return Command{
                    .erase = Erase{
                        .data = i.data,
                    },
                };
            },
            .erase => |e| {
                return Command{
                    .insert = Insert{
                        .data = e.data,
                    },
                };
            },
        }
    }

    pub const Insert = struct {
        data: []const u8,
    };
    pub const Erase = struct {
        data: []const u8,
    };
};

const TextBuffer = struct {
    const TypeSelf = @This();

    mode: Mode,
    cursor: Cursor,
    allocator: *std.mem.Allocator,
    first: *Node,
    last: *Node,

    pub fn NewBlank(allocator: *std.mem.Allocator) !TypeSelf {
        const initialNode = try allocator.create(Node);

        return TypeSelf{
            .mode = .Command,
            .cursor = std.mem.zeroes(Cursor),
            .allocator = allocator,
            .first = initialNode,
            .last = initialNode,
        };
    }

    pub fn apply_command(self: *TypeSelf, command: Command) !void {
        return switch (command) {
            .insert => |i| self.apply_insert(i),
            .erase => |e| self.apply_erase(e),
        };
    }

    fn get_active_node(self: *TypeSelf) !*Node {
        var index: i64 = 0;
        var node: ?*Node = self.first;
        while(node) : ({
                    index += node.text.len;
                    node = nd.next;
                    }) |nd| {
            if(index + nd.text.len > self.cursor.position){
                return nd;
            }
        }
        return error.NodeNotFound;
    }

    fn apply_insert(self: *TypeSelf, command: Command.Insert) !void {
        _ = self;
        _ = command;
    }

    fn apply_erase(self: *TypeSelf, command: Command.Erase) !void {
        _ = self;
        _ = command;
    }

    const Node = struct {
        const TypeNode = @This();
        pub const NODE_LENGTH = 64;

        text_buffer: [NODE_LENGTH]u8,
        text: []u8,
        previous: ?*TypeNode,
        next: ?*TypeNode,
    };
};

pub fn main() !void {}

test "Text Buffer Search" {
    const buffer = TextBuffer.NewBlank()
}
