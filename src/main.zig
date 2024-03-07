const std = @import("std");
const builtin = @import("builtin");
const uefi = std.os.uefi;
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
};

const EfiTPL = enum(usize) {
    application = 4,
    callback = 8,
    notify = 16,
    high_level = 31,
};

const EfiColor = enum(usize) {
    black,
    blue,
    green,
    cyan,
    red,
    magenta,
    brown,
    light_gray,
    dark_gray,
    light_blue,
    light_green,
    light_cyan,
    light_red,
    light_magenta,
    yellow,
    white,

    pub fn bg(self: EfiColor, comptime bgc: EfiColor) usize {
        if (@intFromEnum(bgc) > @intFromEnum(EfiColor.light_gray)) {
            @compileError("Background color can only be from black to brown");
        }

        return @intFromEnum(self) | (@intFromEnum(bgc) << 4);
    }
};

fn print(out: *const uefi.protocol.SimpleTextOutput, buf: []const u8) void {
    const view = std.unicode.Utf8View.init(buf) catch unreachable;
    var iter = view.iterator();

    // rudimentary utf16 writer
    var index: usize = 0;
    var utf16: [256]u16 = undefined;
    while (iter.nextCodepoint()) |rune| {
        if (index + 1 >= utf16.len) {
            utf16[index] = 0;
            _ = out.outputString(utf16[0..index :0]);
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
        _ = out.outputString(utf16[0..index :0]);
    }
}

pub fn checkForError(status: uefi.Status, msg: []const u8) void {
    const cout = uefi.system_table.con_out.?;

    switch (status) {
        .Success => {},
        else => {
            var buf = std.mem.zeroes([128]u8);
            const fmt_msg = std.fmt.bufPrint(
                &buf,
                "[{}] {s}",
                .{ status, msg },
            ) catch "Creating buffer failed\r\n";
            print(cout, fmt_msg);
            hang();
        },
    }
}

const EfiInputKey = uefi.protocol.SimpleTextInput.Key;

const TimerCtx = struct {
    cout: *uefi.protocol.SimpleTextOutput,
};

const DateCtx = struct {
    max_cols: u32,
    max_rows: u32,
    cout: *uefi.protocol.SimpleTextOutput,
    rt_services: *uefi.tables.RuntimeServices,
};

pub fn timerNotify(event: uefi.Event, data: ?*anyopaque) callconv(uefi.cc) void {
    _ = event;
    if (data) |timer_ctx| {
        const timer_data: *TimerCtx = @ptrCast(@alignCast(timer_ctx));
        print(timer_data.cout, "test 123");
    }
}

pub fn print_date(event: uefi.Event, data: ?*anyopaque) callconv(uefi.cc) void {
    _ = event;
    if (data) |date_ctx| {
        const ctx: *DateCtx = @ptrCast(@alignCast(date_ctx));
        var time: uefi.Time = undefined;
        var status = ctx.rt_services.getTime(&time, null);
        checkForError(status, "Couldn't get time!\r\n");

        const save_cols = ctx.cout.mode.cursor_column;
        const save_rows = ctx.cout.mode.cursor_row;
        status = ctx.cout.setCursorPosition(ctx.max_cols - 20, ctx.max_rows - 1);
        checkForError(status, "Couldn't set cursor position!\r\n");

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
            print(ctx.cout, msg);
        }

        status = ctx.cout.setCursorPosition(@intCast(save_cols), @intCast(save_rows));
        checkForError(status, "Couldn't set cursor position 2!\r\n");
    }
}

pub fn main() void {
    const boot_services = uefi.system_table.boot_services.?;
    const rt_services = uefi.system_table.runtime_services;
    var status = std.mem.zeroes(uefi.Status);

    const cout = uefi.system_table.con_out.?;

    status = cout.reset(true);
    checkForError(status, "Failed to reset console out!\r\n");

    status = cout.clearScreen();
    checkForError(status, "Failed to clear screen!\r\n");

    const cin = uefi.system_table.con_in.?;
    status = cin.reset(true);
    checkForError(status, "Failed to clear console in!\r\n");

    status = cout.setAttribute(EfiColor.black.bg(EfiColor.light_gray));
    checkForError(status, "Setting the background and foreground color failed!\r\n");

    status = cout.clearScreen();
    checkForError(status, "Failed to clear screen!\r\n");

    var gop: *uefi.protocol.GraphicsOutput = undefined;

    status = boot_services.locateProtocol(
        &uefi.protocol.GraphicsOutput.guid,
        null,
        @as(*?*anyopaque, @ptrCast(&gop)),
    );
    checkForError(status, "No GOP!\r\n");

    var size_of_info = std.mem.zeroes(usize);
    var info = std.mem.zeroes(uefi.protocol.GraphicsOutput.Mode.Info);
    var ptr = &info;

    status = gop.queryMode(0, &size_of_info, &ptr);
    checkForError(status, "Quering for mode 0 failed!\r\n");

    status = gop.setMode(gop.mode.max_mode - 1);
    checkForError(status, "Failed to set mode to max_mode - 1!\r\n");

    var max_cols: usize = 0;
    var max_rows: usize = 0;
    status = cout.queryMode(0, &max_cols, &max_rows);
    checkForError(status, "Getting rows and cols failed!\r\n");

    status = cout.setMode(0);
    checkForError(status, "Failed to set text mode!\r\n");

    var date_ctx = DateCtx{
        .max_cols = @intCast(max_cols),
        .max_rows = @intCast(max_rows),
        .cout = cout,
        .rt_services = rt_services,
    };
    var date_event: uefi.Event = undefined;

    status = boot_services.createEvent(
        @intFromEnum(EfiEventType.timer) | @intFromEnum(EfiEventType.notify_signal),
        @intFromEnum(EfiTPL.callback),
        print_date,
        &date_ctx,
        &date_event,
    );
    checkForError(status, "Creating event failed!\r\n");
    defer _ = boot_services.closeEvent(date_event);

    status = boot_services.setTimer(date_event, .TimerPeriodic, 10_000_000);
    checkForError(status, "Couldn't set timer interval!\r\n");

    {
        var buf = std.mem.zeroes([1024]u8);
        const msg = std.fmt.bufPrint(
            &buf,
            "Max mode: {}\r\nMode: {}\r\nFramebuffer size: {}\r\n",
            .{
                gop.mode.max_mode,
                gop.mode.mode,
                gop.mode.frame_buffer_size,
            },
        ) catch "Creating buffer failed!\r\n";
        print(cout, msg);
    }

    {
        var buf = std.mem.zeroes([1024]u8);
        const msg = std.fmt.bufPrint(
            &buf,
            "version: {}\r\nhorizontal resolution: {}\r\nvertical resolution: {}\r\nppsl: {}\r\n",
            .{
                ptr.version,
                ptr.horizontal_resolution,
                ptr.vertical_resolution,
                ptr.pixels_per_scan_line,
            },
        ) catch "Creating buffer failed\r\n";
        print(cout, msg);
    }

    var timer_ctx = TimerCtx{ .cout = cout };
    var event: uefi.Event = undefined;

    status = boot_services.createEvent(
        @intFromEnum(EfiEventType.timer) | @intFromEnum(EfiEventType.notify_signal),
        @intFromEnum(EfiTPL.callback),
        timerNotify,
        &timer_ctx,
        &event,
    );
    checkForError(status, "Creating event failed!\r\n");
    defer _ = boot_services.closeEvent(event);

    status = boot_services.setTimer(event, .TimerPeriodic, 10000000);
    checkForError(status, "Couldn't set timer interval!\r\n");

    var timer_ctx2 = TimerCtx{ .cout = cout };
    var event2: uefi.Event = undefined;

    status = boot_services.createEvent(
        @intFromEnum(EfiEventType.timer) | @intFromEnum(EfiEventType.notify_signal),
        @intFromEnum(EfiTPL.callback),
        timerNotify,
        &timer_ctx2,
        &event2,
    );
    checkForError(status, "Creating event failed!\r\n");
    defer _ = boot_services.closeEvent(event2);

    status = boot_services.setTimer(event2, .TimerPeriodic, 20000000);
    checkForError(status, "Couldn't set timer interval!\r\n");

    while (true) {
        print(cout, "Enter any key: \r\n");

        var key: EfiInputKey.Input = undefined;
        while (cin.readKeyStroke(&key) == uefi.Status.NotReady) {}
        print(cout, "Found key!\r\n");

        var buf = std.mem.zeroes([128]u8);
        const msg = std.fmt.bufPrint(&buf, "key pressed: {}\r\n", .{key.unicode_char}) catch "Creating buffer failed!\r\n";
        print(cout, msg);
    }

    hang();
}
