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
const setVideoMode = @import("videomode.zig").setVideoMode;

pub var cout: *uefi.protocol.SimpleTextOutput = undefined;
pub var cin: *uefi.protocol.SimpleTextInput = undefined;
pub var cerr: *uefi.protocol.SimpleTextOutput = undefined;
pub var boot_services: *uefi.tables.BootServices = undefined;
pub var rt_services: *uefi.tables.RuntimeServices = undefined;
pub var gop: *uefi.protocol.GraphicsOutput = undefined;

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
    boot_services.locateProtocol(&uefi.protocol.GraphicsOutput.guid, null, @ptrCast(&gop)).err() catch {};

    cout.setAttribute(DEFAULT_COLOR).err() catch {};

    boot_services.setWatchdogTimer(0, 0x3A7C2D05, 0, null).err() catch {};

    const menu_choices = [_][]const u8{
        "Set Text Mode",
    };
    _ = menu_choices;

    const menu_funcs = [_]*const fn (alloc: std.mem.Allocator) uefi.Status{
        &setTextMode,
    };
    _ = menu_funcs;

    var time = std.mem.zeroes(uefi.Time);
    var time_ctx = TimeCtx{ .time = &time };

    boot_services.createEvent(
        EfiEventType.timer.with(.notify_signal),
        @intFromEnum(EfiTPL.notify),
        &get_time,
        &time_ctx,
        &timer_event,
    ).err() catch {};

    boot_services.setTimer(timer_event, .TimerPeriodic, 10_000_000).err() catch {};

    var max_cols: usize = undefined;
    var max_rows: usize = undefined;
    cout.queryMode(cout.mode.mode, &max_cols, &max_rows).err() catch {};

    setTextMode(alloc).err() catch {};

    // var menu_index: usize = 0;
    const getting_input = true;
    // var current_row: usize = @intCast(cout.mode.cursor_row);

    while (getting_input) {
        cout.setCursorPosition(max_cols - 20, max_rows).err() catch {};
        printArgs(
            alloc,
            "{}-{}-{} {}:{}:{}",
            .{
                time.year,
                time.month,
                time.day,
                time.hour,
                time.minute,
                time.second,
            },
        );
        cout.clearScreen().err() catch {};
    }

    return uefi.Status.Success;
}

pub fn hang() void {
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

const EfiInputKey = uefi.protocol.SimpleTextInput.Key;

const TimeCtx = struct {
    time: *uefi.Time,
};

pub fn get_time(event: uefi.Event, data: ?*anyopaque) callconv(uefi.cc) void {
    _ = event;
    if (data) |date_ctx| {
        const ctx: *TimeCtx = @ptrCast(@alignCast(date_ctx));
        rt_services.getTime(ctx.time, null).err() catch {};
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
