const std = @import("std");
const win32 = @import("win32");

const print = std.debug.print;

const max_bytes = 1048576;

pub fn main() void {
    const stdin = std.io.getStdIn();
    defer stdin.close();

    // check that the session isn't interactive
    if (stdin.isTty()) {
        print("zclip: data must be piped to stdin\n", .{});
        std.process.exit(1);
    }

    var gpalloc = std.heap.DebugAllocator(.{}).init;
    const gpa = gpalloc.allocator();
    defer _ = gpalloc.deinit();

    // open clipboard
    if (win32.system.data_exchange.OpenClipboard(null) != 1) {
        print("zclip: open clipboard failed\n", .{});
        std.process.exit(1);
    }
    // close clipboard as per documentation
    defer if (win32.system.data_exchange.CloseClipboard() != 1) {
        print("zclip: failed to close clipboard\n", .{});
    };

    // empty clipboard first
    if (win32.system.data_exchange.EmptyClipboard() != 1) {
        print("zclip: empty clipboard failed\n", .{});
        std.process.exit(1);
    }

    // read data from stdin
    const data = stdin.readToEndAlloc(gpa, max_bytes) catch {
        print("zclip: input too large - {d} byte limit\n", .{max_bytes});
        std.process.exit(1);
    };
    defer gpa.free(data);

    // allocate memory with the global allocator as per documentation
    const gptr_int = win32.system.memory.GlobalAlloc(.{}, max_bytes + 1);
    if (gptr_int == 0) {
        print("zclip: global alloc failed\n", .{});
        std.process.exit(1);
    }

    // convert this to a zig-useable pointer of u8
    var gptr: [*]u8 = @ptrFromInt(@as(usize, @intCast(gptr_int)));

    for (data, 0..) |byte, i| {
        gptr[i] = byte;
        print("{c}", .{byte});
    }
    print("\n", .{});

    gptr[data.len] = 0;

    // hand the memory to the system
    const result = win32.system.data_exchange.SetClipboardData(1, gptr);
    if (result == null) {
        print("zclip: set clipboard failed\n", .{});
        std.process.exit(1);
    }
}
