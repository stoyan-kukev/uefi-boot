const std = @import("std");
const builtin = @import("builtin");
const uefi = std.os.uefi;

const colors = @import("eficolor.zig");
const DEFAULT_COLOR = colors.DEFAULT_COLOR;
const HIGHLIGHT_COLOR = colors.HIGHLIGHT_COLOR;

pub const ESC_KEY: u16 = 0x17;
pub const UP_ARROW: u16 = 0x1;
pub const DOWN_ARROW: u16 = 0x2;

const setTextMode = @import("textmode.zig").setTextMode;

pub var cout: *uefi.protocol.SimpleTextOutput = undefined;
pub var cin: *uefi.protocol.SimpleTextInput = undefined;
pub var cerr: *uefi.protocol.SimpleTextOutput = undefined;
pub var boot_services: *uefi.tables.BootServices = undefined;
pub var rt_services: *uefi.tables.RuntimeServices = undefined;

var timer_event: uefi.Event = undefined;

pub fn main() uefi.Status {
    var memory_buffer: [100000]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&memory_buffer);
    const alloc = fba.allocator();

    boot_services = uefi.system_table.boot_services.?;
    rt_services = uefi.system_table.runtime_services;

    cout = uefi.system_table.con_out.?;
    cin = uefi.system_table.con_in.?;
    cerr = uefi.system_table.std_err.?;

    cout.setAttribute(DEFAULT_COLOR).err() catch {};

    boot_services.setWatchdogTimer(0, 0x3A7C2D05, 0, null).err() catch {};

    const menu_choices = [_][]const u8{
        "Set Text Mode",
    };

    const menu_funcs = [_]*const fn (alloc: std.mem.Allocator) uefi.Status{
        &setTextMode,
    };

    setTextMode(alloc).err() catch {};

    while (true) {
        cout.clearScreen().err() catch {};

        var max_cols: usize = undefined;
        var max_rows: usize = undefined;
        cout.queryMode(cout.mode.mode, &max_cols, &max_rows).err() catch {};

        var date_ctx = DateCtx{
            .max_cols = @intCast(max_cols),
            .max_rows = @intCast(max_rows),
        };

        boot_services.createEvent(
            EfiEventType.timer.with(.notify_signal),
            @intFromEnum(EfiTPL.notify),
            &print_date,
            &date_ctx,
            &timer_event,
        ).err() catch {};

        boot_services.setTimer(timer_event, .TimerPeriodic, 10_000_000).err() catch {};

        cout.setCursorPosition(0, max_rows - 3).err() catch {};
        print("Up/Down Arrow = Move Cursor\r\nEnter = Select\r\nEscape = Go Back");

        cout.setCursorPosition(0, 0).err() catch {};
        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};
        printArgs(alloc, "{s}\r\n", .{menu_choices[0]});

        cout.setAttribute(DEFAULT_COLOR).err() catch {};
        for (1..menu_choices.len) |i| {
            printArgs(alloc, "{}\r\n", .{menu_choices[i]});
        }

        const min_row: usize = 0;
        const max_row: usize = @intCast(cout.mode.cursor_row);

        cout.setCursorPosition(0, 0).err() catch {};
        var getting_input = true;
        while (getting_input) {
            var current_row: usize = @intCast(cout.mode.cursor_row);
            const key = getKey();
            printArgs(alloc, "scan_code: {}\r\nchar_code: {}\r\n", .{ key.input.scan_code, key.input.unicode_char });
            hang();

            switch (key.input.scan_code) {
                UP_ARROW => {
                    if (current_row - 1 >= min_row) {
                        // De-highlight current row, move up 1 row, highlight new row
                        cout.setAttribute(DEFAULT_COLOR).err() catch {};
                        printArgs(alloc, "{s}\r", .{menu_choices[current_row]});

                        current_row -= 1;
                        cout.setCursorPosition(0, current_row).err() catch {};
                        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};
                        printArgs(alloc, "{s}\r", .{menu_choices[current_row]});

                        // Reset colors
                        cout.setAttribute(DEFAULT_COLOR).err() catch {};
                    }
                    break;
                },
                DOWN_ARROW => {
                    if (current_row + 1 <= max_row) {
                        // De-highlight current row, move up 1 row, highlight new row
                        cout.setAttribute(DEFAULT_COLOR).err() catch {};
                        printArgs(alloc, "{s}\r", .{menu_choices[current_row]});

                        current_row += 1;
                        cout.setCursorPosition(0, current_row).err() catch {};
                        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};
                        printArgs(alloc, "{s}\r", .{menu_choices[current_row]});

                        // Reset colors
                        cout.setAttribute(DEFAULT_COLOR).err() catch {};
                    }
                    break;
                },
                ESC_KEY => {
                    boot_services.closeEvent(timer_event).err() catch {};
                    rt_services.resetSystem(.ResetShutdown, .Success, 0, null);
                    break;
                },
                else => {
                    if (key.input.scan_code == 0x13) {
                        menu_funcs[current_row](alloc).err() catch |err| {
                            printArgs(alloc, "ERROR {}\r\n Press any key to go back...", .{err});
                        };

                        getting_input = false;
                    }
                    break;
                },
            }
        }
    }

    return uefi.Status.Success;
}

fn hang() void {
    while (true) {
        asm volatile ("pause");
    }
}

const EfiEventType = enum(u32) {
    timer = 0x8000_0000,
    runtime = 0x4000_0000,
    notify_wait = 0x0000_0100,
    notify_signal = 0x0000_0200,
    exit_boot_services = 0x0000_0201,
    virtual_address_change = 0x6000_0202,

    pub fn with(self: EfiEventType, comptime effect: EfiEventType) u32 {
        // switch (self) {
        //     .timer, .runtime => {
        //         switch (effect) {
        //             .notify_wait, .notify_signal, .exit_boot_services => {},
        //             else => @compileError("Effect needs to be either notify_(wait|signal) or exit_boot_services"),
        //         }
        //     },
        //     else => @compileError("Self needs to be either timer or runtime"),
        // }

        return @intFromEnum(self) | @intFromEnum(effect);
    }
};

const EfiTPL = enum(usize) {
    application = 4,
    callback = 8,
    notify = 16,
    high_level = 31,
};

pub fn getKey() uefi.protocol.SimpleTextInput.Key {
    var events: [1]uefi.Event = undefined;
    events[0] = cin.wait_for_key;

    var index: usize = undefined;
    boot_services.waitForEvent(1, &events, &index).err() catch {};

    var key: uefi.protocol.SimpleTextInput.Key = undefined;
    if (index == 0) cin.readKeyStroke(&key.input).err() catch {};

    return key;
}

pub fn print(buf: []const u8) void {
    const view = std.unicode.Utf8View.init(buf) catch unreachable;
    var iter = view.iterator();

    // rudimentary utf16 writer
    var index: usize = 0;
    var utf16: [256]u16 = undefined;
    while (iter.nextCodepoint()) |rune| {
        if (index + 1 >= utf16.len) {
            utf16[index] = 0;
            _ = cout.outputString(utf16[0..index :0]);
            index = 0;
        }

        if (rune < 0x10000) {
            if (rune == '\n') {
                utf16[index] = '\r';
                index += 1;
            }

            utf16[index] = @intCast(rune);
            index += 1;
        } else {
            const high = @as(u16, @intCast((rune - 0x10000) >> 10)) + 0xD800;
            const low = @as(u16, @intCast(rune & 0x3FF)) + 0xDC00;
            switch (builtin.cpu.arch.endian()) {
                .little => {
                    utf16[index] = high;
                    utf16[index] = low;
                },
                .big => {
                    utf16[index] = low;
                    utf16[index] = high;
                },
            }
            index += 2;
        }
    }

    if (index != 0) {
        utf16[index] = 0;
        _ = cout.outputString(utf16[0..index :0]);
    }
}

// pub fn checkForError(status: uefi.Status, msg: []const u8) void {
//     switch (status) {
//         .Success => {},
//         else => {
//             var buf = std.mem.zeroes([128]u8);
//             const fmt_msg = std.fmt.bufPrint(
//                 &buf,
//                 "[{}] {s}",
//                 .{ status, msg },
//             ) catch "Creating buffer failed\r\n";
//             print(fmt_msg);
//             hang();
//         },
//     }
// }

const EfiInputKey = uefi.protocol.SimpleTextInput.Key;

const DateCtx = struct {
    max_cols: u32,
    max_rows: u32,
};

pub fn print_date(event: uefi.Event, data: ?*anyopaque) callconv(uefi.cc) void {
    _ = event;
    if (data) |date_ctx| {
        const ctx: *DateCtx = @ptrCast(@alignCast(date_ctx));
        var time: uefi.Time = undefined;
        rt_services.getTime(&time, null).err() catch {};

        const save_cols = cout.mode.cursor_column;
        const save_rows = cout.mode.cursor_row;
        cout.setCursorPosition(ctx.max_cols - 20, ctx.max_rows - 1).err() catch {};

        {
            var buf = std.mem.zeroes([128]u8);
            const msg = std.fmt.bufPrint(
                &buf,
                "{}-{}-{} {}:{}:{}",
                .{
                    time.year,
                    time.month,
                    time.day,
                    time.hour,
                    time.minute,
                    time.second,
                },
            ) catch "Creating buffer failed\r\n";
            print(msg);
        }

        cout.setCursorPosition(@intCast(save_cols), @intCast(save_rows)).err() catch {};
    }
}

pub fn printArgs(
    alloc: std.mem.Allocator,
    comptime msg: []const u8,
    args: anytype,
) void {
    const utf_text = std.fmt.allocPrint(alloc, msg, args) catch unreachable;
    defer alloc.free(utf_text);

    const text = std.unicode.utf8ToUtf16LeAllocZ(alloc, utf_text) catch unreachable;
    defer alloc.free(text);

    cout.outputString(text).err() catch {};
}
