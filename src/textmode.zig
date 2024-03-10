const std = @import("std");
const uefi = std.os.uefi;

const common = @import("main.zig");
const colors = @import("eficolor.zig");

const DEFAULT_COLOR = colors.DEFAULT_COLOR;
const HIGHLIGHT_COLOR = colors.HIGHLIGHT_COLOR;

const print = common.print;
const printArgs = common.printArgs;
const getKey = common.getKey;

const ESC_KEY = common.ESC_KEY;
const UP_ARROW = common.UP_ARROW;
const DOWN_ARROW = common.DOWN_ARROW;

const TextModeInfo = struct {
    cols: usize,
    rows: usize,
};

pub fn setTextMode(alloc: std.mem.Allocator) uefi.Status {
    const cout = common.cout;
    var text_modes = std.mem.zeroes([30]TextModeInfo);
    var menu_index: usize = 0;

    while (true) {
        cout.clearScreen().err() catch {};

        print("Text mode information\r\n");
        var max_cols: usize = undefined;
        var max_rows: usize = undefined;

        cout.queryMode(cout.mode.mode, &max_cols, &max_rows).err() catch {};

        printArgs(
            alloc,
            "Max Mode: {}\r\nCurrent Mode: {}\r\nAttribute: {}\r\nCursor Column: {}\r\nCursor Row: {}\r\nCursor Visible: {}\r\nColumns: {}\r\nRows: {}\r\n",
            .{
                cout.mode.max_mode,
                cout.mode.mode,
                cout.mode.attribute,
                cout.mode.cursor_column,
                cout.mode.cursor_row,
                cout.mode.cursor_visible,
                max_cols,
                max_rows,
            },
        );

        print("Available text modes:\r\n");

        const menu_top: usize = @intCast(cout.mode.cursor_row);
        var menu_bottom = max_rows;

        cout.setCursorPosition(0, menu_bottom - 3).err() catch {};
        print("Up/Down Arrow = Move Cursor\r\nEnter = Select\r\nEscape = Go Back");

        cout.setCursorPosition(0, menu_top).err() catch {};

        menu_bottom -= 5;
        var menu_len = menu_bottom - menu_top;

        const max_mode = cout.mode.max_mode;
        if (max_mode < menu_len) {
            menu_bottom = menu_top + max_mode - 1;
            menu_len = menu_bottom - menu_top;
        }

        {
            var i: usize = 0;
            while (i < text_modes.len and i < max_mode) : (i += 1) {
                cout.queryMode(i, @constCast(&text_modes[i].cols), @constCast(&text_modes[i].rows)).err() catch {};
            }
        }

        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};
        printArgs(alloc, "Mode 0: {}x{}\r\n", .{ text_modes[0].cols, text_modes[0].rows });

        cout.setAttribute(DEFAULT_COLOR).err() catch {};
        for (1..menu_len + 1) |i| {
            printArgs(alloc, "Mode {}: {}x{}\r\n", .{ i, text_modes[i].cols, text_modes[i].rows });
        }

        cout.setCursorPosition(0, menu_top).err() catch {};
        var getting_input = true;
        while (getting_input) {
            var current_row: usize = @intCast(cout.mode.cursor_row);

            const key = getKey();
            switch (key.input.scan_code) {
                ESC_KEY => return uefi.Status.Success,
                UP_ARROW => {
                    if (current_row == menu_top and menu_index > 0) {
                        print("                                     \r");

                        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};

                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{ menu_index, text_modes[menu_index - 1].cols, text_modes[menu_index - 1].rows });

                        cout.setAttribute(DEFAULT_COLOR).err() catch {};

                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{ menu_index, text_modes[menu_index].cols, text_modes[menu_index].rows });

                        menu_index -= 1;
                        cout.setCursorPosition(0, menu_top).err() catch {};
                    } else if (current_row - 1 >= menu_top) {
                        print("                                     \r");
                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{ menu_index, text_modes[menu_index].cols, text_modes[menu_index].rows });

                        menu_index -= 1;
                        current_row -= 1;

                        cout.setCursorPosition(0, current_row).err() catch {};
                        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};
                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{ menu_index, text_modes[menu_index].cols, text_modes[menu_index].rows });
                    }

                    cout.setAttribute(DEFAULT_COLOR).err() catch {};
                    break;
                },
                DOWN_ARROW => {
                    if (current_row == menu_bottom and menu_index < max_mode - 1) {
                        menu_index -= menu_len - 1;

                        cout.setCursorPosition(0, menu_top).err() catch {};

                        for (0..menu_len) |_| {
                            print("                                     \r");
                            printArgs(alloc, "Mode {}: {}x{}\r\n", .{ menu_index, text_modes[menu_index].cols, text_modes[menu_index].rows });

                            menu_index += 1;
                        }

                        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};
                        print("                                     \r");
                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{ menu_index, text_modes[menu_index].cols, text_modes[menu_index].rows });
                    } else if (current_row + 1 <= menu_bottom) {
                        print("                                     \r");
                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{ menu_index, text_modes[menu_index].cols, text_modes[menu_index].rows });

                        menu_index += 1;
                        current_row += 1;

                        cout.setCursorPosition(0, current_row).err() catch {};
                        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};
                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{ menu_index, text_modes[menu_index].cols, text_modes[menu_index].rows });
                    }

                    cout.setAttribute(DEFAULT_COLOR).err() catch {};
                    break;
                },
                else => {
                    if (key.input.unicode_char == '\r' and text_modes[menu_index].cols != 0) {
                        cout.setMode(menu_index).err() catch {};
                        cout.queryMode(menu_index, &text_modes[menu_index].cols, &text_modes[menu_index].rows).err() catch {};
                        cout.clearScreen().err() catch {};

                        getting_input = false;
                        menu_index = 0;
                    }
                    break;
                },
            }
        }

        return uefi.Status.Success;
    }
}
