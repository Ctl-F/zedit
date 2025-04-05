const std = @import("std");
const ncur = @cImport(@cInclude("curses.h"));
const loc = @cImport(@cInclude("locale.h"));



// TODO: Finish Insert
// TODO: Delete
// TODO: Cursor Movement
// TODO: Selection
// TODO: Undo/Redo Stack
// TODO: Copy, Cut, Paste
// TODO: Display
// TODO: Binary Search for node lookup
// TODO: Saving, Loading
// TODO: Searching
// TODO: Sort+Defragment on Save (double buffered approach if possible)
// TODO: Custom Node Allocator
// TODO: Syntax Highlighting
// TODO: Function+Public Const lookup
// TODO: Integrated Terminal
// TODO: Configuration for projects and keybinding for quick script

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
    allocator: std.mem.Allocator,
    first: *Node,
    last: *Node,

    pub fn NewBlank(allocator: std.mem.Allocator) !TypeSelf {
        const initialNode = try allocator.create(Node);
        initialNode.* = std.mem.zeroes(Node);

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

    fn get_active_node(self: *TypeSelf) CursorPositionInfo {
        var remaining = self.cursor.position;
        var node: ?*Node = self.first;
        while (node) |nd| {
            if (remaining < nd.text.len) {
                return CursorPositionInfo{
                    .node = node,
                    .offset = @as(usize, @intCast(remaining)),
                };
            }

            remaining -= @intCast(nd.text.len);
            node = nd.next;
            if (node == null) {
                break;
            }
        }

        return CursorPositionInfo{
            .node = null,
            .offset = 0,
        };
    }

    fn apply_insert(self: *TypeSelf, command: Command.Insert) !void {
        const cursorInfo = self.get_active_node();
        
        defer self.cursor.position += @intCast(command.data.len);

        if (cursorInfo.node) |nod| {
            // repeat until all the text is inserted:
            // 1: Insert as much text as possible into the current node
            // 2: Insert a new node (if needed)

            var selNode: *Node = nod;
            var curOff = cursorInfo.offset;

            if(selNode.total_free_space() == 0){
                // insert a new node already
                selNode = try self.insert_right(selNode);
                curOff = 0;
            }

            var view: []const u8 = command.data;
            while(view.len > 0){
                // if the selected node has enough free space
                // then we can insert it fine
                if(selNode.total_free_space() >= view.len){
                    insert_text(selNode, curOff, view);
                    break;
                }


                // at this point we already know that the current
                // node doesn't have enough space to insert the whole
                // text so we're going to have to split the node
                const nextNode = try self.split_node(selNode, curOff);
                
                // now we add what does fit
                const slice = view[0..selNode.total_free_space()];
                insert_text(selNode, curOff, slice);
                
                view = view[slice.len..];
                selNode = nextNode;
            }
        } else {
            return self.append_to_end(command);
        }
    }

    pub fn length(self: TypeSelf) usize {
        var node: ?*Node = self.first;
        var count: usize = 0;
        while(node) |nd| {
            count += nd.text.len;
            node = nd.next;
        }
        return count;
    }

    
    pub fn get_text(self: TypeSelf, buffer: []u8) !void {
        const len = self.length();
        
        if(buffer.len < len){
            return error.InsufficientBuffer;
        }

        var node: ?*Node = self.first;
        
        var start: usize = 0;
        var end: usize = 0;
        while(node) |nd| {
            end = start + nd.text.len;
            @memcpy(buffer[start..end], nd.text);
            start = end;
            node = nd.next;
        }
    }

    /// Splits the node at a given offset returning the newly created node
    /// the original node will stay the same, except it'll have some of its
    /// data moved over to the two node.
    /// take care not to leave empty nodes because they'll break cursor logic
    fn split_node(self: *TypeSelf, node: *Node, offset: usize) !*Node {
        std.debug.assert(offset < node.text.len);
        
        const right_text: []const u8 = node.text[offset..];
        const newNode = try self.insert_right(node);
    
        @memcpy(newNode.text_buffer[0..right_text.len], right_text);
        newNode.text = newNode.text_buffer[0..right_text.len];

        node.text = node.text[0..offset];
        return newNode;
    }

    fn insert_right(self: *TypeSelf, node: *Node) !*Node {
        const newNode = try self.allocator.create(Node);
        newNode.* = std.mem.zeroes(Node);

        if(node == self.first and self.first == self.last){
            self.last = newNode;
        }
        if(node.next) |nxt| {
            newNode.next = nxt;
            nxt.previous = newNode;
        }
        node.next = newNode;
        newNode.previous = node;

        return newNode;
    }

    fn append_to_end(self: *TypeSelf, command: Command.Insert) !void {
        var section_begin: usize = 0;

        while (section_begin < command.data.len) {
            const section_end: usize = @min(section_begin + Node.NODE_LENGTH, command.data.len);
            const section: []const u8 = command.data[section_begin..section_end];

            const node = try self.allocator.create(Node);
            node.* = std.mem.zeroes(Node);

            @memcpy(node.text_buffer[0..section.len], section);
            node.text = node.text_buffer[0..section.len];

            if (self.last == self.first) {
                self.first.next = node;
                node.previous = self.first;
                self.last = node;
            } else {
                if (self.last.previous) |prev| {
                    prev.next = node;
                    node.previous = prev;
                    self.last = node;
                } else {
                    unreachable;
                }
            }

            section_begin = section_end;
        }

        self.cursor.position += @intCast(command.data.len);
    }

    fn insert_text(node: *Node, offset: u64, text: []const u8) void {
        const total_free = node.total_free_space();
        const new_length = node.text.len + text.len;

        std.debug.assert(new_length <= node.text_buffer.len);
        std.debug.assert(total_free >= text.len);
        std.debug.assert(offset + text.len <= node.text_buffer.len);
        std.debug.assert(offset <= node.text.len);

        var tmp_buffer: [Node.NODE_LENGTH]u8 = undefined;

        const pre_text: []u8 = node.text_buffer[0..offset];
        const post_text: []u8 = node.text_buffer[offset..node.text.len];

        const pre_begin = 0;
        const pre_end = pre_begin + offset;
        const text_begin = pre_end;
        const text_end = text_begin + text.len;
        const post_begin = text_end;
        const post_end = post_begin + post_text.len;

        @memcpy(tmp_buffer[pre_begin..pre_end], pre_text);
        @memcpy(tmp_buffer[text_begin..text_end], text);
        @memcpy(tmp_buffer[post_begin..post_end], post_text);

        @memcpy(node.text_buffer[0..new_length], tmp_buffer[0..new_length]);
        node.text = node.text_buffer[0..new_length];
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

        pub inline fn total_free_space(self: *TypeNode) usize {
            return self.text_buffer.len - self.text.len;
        }
    };

    const CursorPositionInfo = struct {
        node: ?*Node,
        offset: usize,
    };
};

pub fn main() !void {}

test "get_active_node returns expected CursorPositionInfo" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    //std.debug.print("Allocating text buffer\n", .{});
    var buffer = try TextBuffer.NewBlank(allocator);

    //std.debug.print("Allocating nodes\n", .{});
    const node1 = buffer.first;
    const node2 = try allocator.create(TextBuffer.Node);
    const node3 = try allocator.create(TextBuffer.Node);

    node2.* = std.mem.zeroes(TextBuffer.Node);
    node3.* = std.mem.zeroes(TextBuffer.Node);

    const text = "abcdefghijkl";
    //std.debug.print("Copying data to nodes\n", .{});
    @memcpy(node1.text_buffer[0..3], text[0..3]);
    @memcpy(node2.text_buffer[0..4], text[3..7]);
    @memcpy(node3.text_buffer[0..5], text[7..12]);

    node1.text = node1.text_buffer[0..3];
    node2.text = node2.text_buffer[0..4];
    node3.text = node3.text_buffer[0..5];

    node1.next = node2;
    node2.previous = node1;

    node2.next = node3;
    node3.previous = node2;

    buffer.last = node3;

    //std.debug.print("Test 0 get_active_node()\n", .{});
    // case 1: Cursor at offset 0
    buffer.cursor.position = 0;
    const info0 = buffer.get_active_node();
    try std.testing.expect(info0.node == node1);
    try std.testing.expectEqual(@as(usize, 0), info0.offset);

    //std.debug.print("Test 1 get_active_node()\n", .{});
    // case 2: cursor at offset 3 (start of node 2)
    buffer.cursor.position = 3;
    const info1 = buffer.get_active_node();
    try std.testing.expect(info1.node == node2);
    try std.testing.expectEqual(@as(usize, 0), info1.offset);

    //std.debug.print("Test 2 get_active_node()\n", .{});
    // case 3: cursor at offset 6 (mid node2)
    buffer.cursor.position = 6;
    const info2 = buffer.get_active_node();
    try std.testing.expect(info2.node == node2);
    try std.testing.expectEqual(@as(usize, 3), info2.offset);

    //std.debug.print("Test 3 get_active_node()\n", .{});
    // case 4: cursor at offset 12 (past end of final node)
    buffer.cursor.position = 12;
    const info3 = buffer.get_active_node();
    try std.testing.expect(info3.node == null);
    try std.testing.expectEqual(@as(usize, 0), info3.offset);

    //std.debug.print("End get_active_node() tests\n", .{});
}

test "insert_text simulating keystrokes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffer = try TextBuffer.NewBlank(allocator);

    const str: []const u8 = "Hello";
    
    const commands = [_] Command {
        .{ .insert = .{ .data = str[0..1], }, },
        .{ .insert = .{ .data = str[1..2], }, },
        .{ .insert = .{ .data = str[2..], }, },
    };

    for(commands) |cmd| {
        try buffer.apply_command(cmd);
    }

    std.debug.print("Attempting to grab length and text\n", .{});

    const len = buffer.length();
    var buf: [64]u8 = undefined;
    try buffer.get_text(buf[0..len]);
    
    std.debug.print("Results: len {d}, exp {d}\n", .{len, str.len});

    try std.testing.expect(len == str.len);
    try std.testing.expectEqualStrings(str, buf[0..len]);

    std.debug.print("Keystroke Simulation done: {s}\n", .{buf[0..len]});
}

test "apply_command with Insert to end" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    //std.debug.print("Allocating new text buffer\n", .{});
    var buffer = try TextBuffer.NewBlank(allocator);

    const full_string: []const u8 = "012345678901234567890123456789 012345678901234567890123456789 ab";

    //std.debug.print("Copying data to first node in text buffer.\n", .{});
    @memcpy(&buffer.first.text_buffer, full_string);
    buffer.first.text = &buffer.first.text_buffer;

    //std.debug.print("Creating insert command\n", .{});
    const test_text = "Hello World";
    const insert_command = Command{
        .insert = Command.Insert{
            .data = test_text[0..],
        },
    };

    //std.debug.print("Applying command\n", .{});
    buffer.cursor.position = 64;
    try buffer.apply_command(insert_command);

    try std.testing.expect(buffer.first != buffer.last);
    try std.testing.expectEqualStrings(buffer.first.text, full_string);
    try std.testing.expectEqualStrings(buffer.last.text, test_text);

    //std.debug.print("End apply_command() tests\n", .{});
}
