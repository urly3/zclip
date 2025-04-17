const std = @import("std");
const win32 = @import("win32");

const print = std.debug.print;

const max_bytes = 1048576;

pub fn main() u8 {
    const stdin = std.io.getStdIn();
    defer stdin.close();

    var gpalloc = std.heap.DebugAllocator(.{}).init;
    const gpa = gpalloc.allocator();
    defer _ = gpalloc.deinit();

    var args = std.process.argsWithAllocator(gpa) catch unreachable;
    defer args.deinit();
    args = args;

    if (args.next() == null) {
        print("zclip: not even a 0th arg?\n", .{});
        return 1;
    }

    const state = parseArgs(&args);
    if (state.help) {
        print(
            \\zlcip: copies piped in text to the clipboard
            \\valid arguments
            \\  -h [--help]    print this message
            \\  -l [--lower]   lowercase the text
            \\  -u [--upper]   uppercase the text
            \\  -t [--trim]    trim whitespace from the text
            \\  -q [--quiet]   doesn't print the text
            \\
        , .{});
        return 0;
    }

    // check that the session isn't interactive
    if (stdin.isTty()) {
        print("zclip: data must be piped to stdin\n", .{});
        return 1;
    }

    // read data from stdin
    const ogdata = stdin.readToEndAlloc(gpa, max_bytes) catch {
        print("zclip: input too large - {d} byte limit\n", .{max_bytes});
        return 1;
    };
    defer gpa.free(ogdata);

    var data = ogdata;
    if (data.len <= 0) {
        print("zclip: input was empty\n", .{});
        return 1;
    }

    var index: usize = 0;
    if (state.lower and state.upper) { // esponge case
        index = 0;
        var upper: bool = false;

        while (index < data.len) : (index += 1) {
            const char = data[index];
            if (char >= 'a' and char <= 'z') {
                if (upper) {
                    data[index] = char - 32;
                }
                upper = !upper;
            } else if (char >= 'A' and char <= 'Z') {
                if (!upper) {
                    data[index] = char + 32;
                }
                upper = !upper;
            }
        }
    } else {
        if (state.lower) { // lowercase
            index = 0;
            while (index < data.len) : (index += 1) {
                const char = data[index];
                if (char >= 65 and char <= 90) {
                    data[index] = char + 32;
                }
            }
        }

        if (state.upper) { // upper case
            index = 0;
            while (index < data.len) : (index += 1) {
                const char = data[index];
                if (char >= 97 and char <= 122) {
                    data[index] = char - 32;
                }
            }
        }
    }

    if (state.trim) { // trim
        var start: usize = 0;
        var end: usize = data.len;

        index = 0;
        while (index < data.len) : ({
            index += 1;
            start += 1;
        }) {
            if (data[index] != ' ') {
                break;
            }
        }

        index = data.len - 1;
        while (index < data.len) : ({
            index -= 1;
            end -= 1;
        }) {
            if (data[index] != ' ') {
                break;
            }
        }
        data = data[start..end];
    }

    // allocate memory with the global allocator as per documentation
    const gptr_int = win32.system.memory.GlobalAlloc(.{}, data.len);
    if (gptr_int == 0) {
        print("zclip: global alloc failed\n", .{});
        return 1;
    }

    // open clipboard
    if (win32.system.data_exchange.OpenClipboard(null) != 1) {
        print("zclip: open clipboard failed\n", .{});
        return 1;
    }
    // close clipboard as per documentation
    defer if (win32.system.data_exchange.CloseClipboard() != 1) {
        print("zclip: failed to close clipboard\n", .{});
    };

    // empty clipboard first
    if (win32.system.data_exchange.EmptyClipboard() != 1) {
        print("zclip: empty clipboard failed\n", .{});
        return 1;
    }

    // convert this to a zig-useable pointer of u8s
    var gptr: [*]u8 = @ptrFromInt(@as(usize, @intCast(gptr_int)));

    for (data, 0..) |byte, i| {
        gptr[i] = byte;
    }
    gptr[data.len] = 0;

    // print result
    if (!state.quiet) {
        print("{s}\n", .{data});
    }

    // hand the memory to the system
    const result = win32.system.data_exchange.SetClipboardData(1, gptr);
    if (result == null) {
        print("zclip: set clipboard failed\n", .{});
        return 1;
    }

    return 0;
}

fn parseArgs(args: *std.process.ArgIterator) ArgsState {
    var state: ArgsState = .init;

    while (args.next()) |cur| {
        for (available_args, 0..) |arg, index| {
            if (std.mem.eql(u8, cur, arg)) {
                switch (index) {
                    0, 1 => state.help = true,
                    2, 3 => state.lower = true,
                    4, 5 => state.upper = true,
                    6, 7 => state.trim = true,
                    8, 9 => state.quiet = true,
                    else => unreachable,
                }
                break;
            }
        }
    }

    return state;
}

const ArgsState = struct {
    help: bool,
    lower: bool,
    upper: bool,
    trim: bool,
    quiet: bool,

    const init: @This() = .{
        .help = false,
        .lower = false,
        .upper = false,
        .trim = false,
        .quiet = false,
    };
};

const available_args = [_][:0]const u8{
    "--help", // 0
    "-h", // 1
    "--lower", // 2
    "-l", // 3
    "--upper", // 4
    "-u", // 5
    "--trim", // 6
    "-t", // 7
    "--quiet", // 8
    "-q", // 9
};
