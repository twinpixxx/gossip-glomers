const std = @import("std");

const Body = struct {
    type: MessageType,
    msg_id: ?u64 = null,
    in_reply_to: ?u64 = null,
    echo: ?[]const u8 = null,
    node_id: ?[]const u8 = null,
    node_ids: ?[][]const u8 = null,
    id: ?u64 = null
};

const Message = struct {
    src: []const u8,
    dest: []const u8,
    body: Body,
};

const MessageType = enum {
    init,
    init_ok,
    echo,
    echo_ok,
    generate,
    generate_ok,
};

var node_id: []const u8 = "";

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(allocator);

    var read_buf: [4096]u8 = undefined;

    while (true) {
        const n = try std.posix.read(std.posix.STDIN_FILENO, &read_buf);
        if (n == 0) break;

        for (read_buf[0..n]) |byte| {
            if (byte == '\n') {
                if (line_buf.items.len > 0) {
                    try handleMessage(allocator, line_buf.items);
                    line_buf.clearRetainingCapacity();
                }
            } else {
                try line_buf.append(allocator, byte);
            }
        }
    }

    if (line_buf.items.len > 0) {
        try handleMessage(allocator, line_buf.items);
    }
}

fn reply(msg: Message, body: Body) !void {
    const response = Message{
        .src = msg.dest,
        .dest = msg.src,
        .body = body,
    };

    var out_buf: [65536]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&out_buf);
    try std.json.Stringify.value(response, .{ .emit_null_optional_fields = false }, &writer);
    try writer.writeByte('\n');

    const out = writer.buffered();
    _ = std.c.write(std.posix.STDOUT_FILENO, out.ptr, out.len);
}

fn handleMessage(allocator: std.mem.Allocator, line: []const u8) !void {
    const parsed = try std.json.parseFromSlice(Message, allocator, line, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const msg = parsed.value;

    switch (msg.body.type) {
      .init => {
          node_id = try allocator.dupe(u8, msg.body.node_id orelse "");
          try reply(msg, .{
              .type = MessageType.init_ok,
              .in_reply_to = msg.body.msg_id,
          });
      },

      .echo => try reply(msg, .{
          .type = MessageType.echo_ok,
          .msg_id = msg.body.msg_id,
          .in_reply_to = msg.body.msg_id,
          .echo = msg.body.echo,
      }),

      .generate => try reply(msg, .{
          .type = MessageType.generate_ok,
          .msg_id = msg.body.msg_id,
          .in_reply_to = msg.body.msg_id,
          .id = generateId(),
      }),

      else => {},
    }
}

fn generateId() u64 {
    var seed: [std.Random.ChaCha.secret_seed_length]u8 = undefined;
    std.c.arc4random_buf(&seed, seed.len);
    var csprng = std.Random.ChaCha.init(seed);
    return csprng.random().int(u64);
}
