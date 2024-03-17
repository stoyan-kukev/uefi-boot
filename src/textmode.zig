const std = @import("std");
const uefi = std.os.uefi;

const common = @import("main.zig");
const colors = @import("eficolor.zig");

const DEFAULT_COLOR = colors.DEFAULT_COLOR;
const HIGHLIGHT_COLOR = colors.HIGHLIGHT_COLOR;
const EfiColor = colors.EfiColor;

const print = common.print;
const printArgs = common.printArgs;
const getKey = common.getKey;
const hang = common.hang;

const ESC_KEY = common.ESC_KEY;
const UP_ARROW = common.UP_ARROW;
const DOWN_ARROW = common.DOWN_ARROW;

const TextModeInfo = struct {
    cols: usize,
    rows: usize,
};

pub fn setTextMode(alloc: std.mem.Allocator) uefi.Status {
    const cout = common.cout;

    var text_modes = std.ArrayList(TextModeInfo).initCapacity(alloc, cout.mode.max_mode) catch unreachable;
    text_modes.expandToCapacity();

    while (true) {
        cout.clearScreen().err() catch {};

        print("Text mode information\r\n\r\n");
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

        print("\r\nAvailable text modes:\r\n");

        for (text_modes.items, 0..) |*text_mode, i| {
            cout.queryMode(i, &text_mode.cols, &text_mode.rows).err() catch {};
        }

        for (text_modes.items, 0..) |text_mode, i| {
            printArgs(alloc, "Mode {}: {}x{}\r\n", .{ i, text_mode.cols, text_mode.rows });
        }

        const menu_top: usize = @intCast(cout.mode.cursor_row);
        const menu_bottom = max_rows - 4;
        const menu_len = menu_bottom - menu_top;
        cout.setCursorPosition(0, menu_top).err() catch {};

        var menu_index: usize = 0;
        var getting_input = true;
        var current_row: usize = @intCast(cout.mode.cursor_row);
        while (getting_input) {
            const key = getKey();
            switch (key.input.scan_code) {
                ESC_KEY => return uefi.Status.Success,
                UP_ARROW => {
                    if (current_row >= menu_top and menu_index > 0) {
                        cout.setAttribute(DEFAULT_COLOR).err() catch {};

                        print("                                ");
                        cout.setCursorPosition(0, current_row).err() catch {};
                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{
                            menu_index,
                            text_modes.items[menu_index].cols,
                            text_modes.items[menu_index].rows,
                        });

                        menu_index -= 1;
                        current_row -= 1;
                        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};

                        cout.setCursorPosition(0, current_row).err() catch {};
                        print("                                ");

                        cout.setCursorPosition(0, current_row).err() catch {};
                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{
                            menu_index,
                            text_modes.items[menu_index].cols,
                            text_modes.items[menu_index].rows,
                        });
                    }
                },

                DOWN_ARROW => {
                    if (current_row <= menu_bottom and menu_index < menu_len) {
                        cout.setAttribute(DEFAULT_COLOR).err() catch {};

                        print("                                \r\n");
                        cout.setCursorPosition(0, current_row).err() catch {};
                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{
                            menu_index,
                            text_modes.items[menu_index].cols,
                            text_modes.items[menu_index].rows,
                        });

                        menu_index += 1;
                        current_row += 1;
                        cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};

                        cout.setCursorPosition(0, current_row).err() catch {};
                        print("                                \r\n");

                        cout.setCursorPosition(0, current_row).err() catch {};
                        printArgs(alloc, "Mode {}: {}x{}\r\n", .{
                            menu_index,
                            text_modes.items[menu_index].cols,
                            text_modes.items[menu_index].rows,
                        });
                    }
                },
                else => {
                    if (key.input.unicode_char == 13 and text_modes.items[menu_index].cols != 0) {
                        cout.setMode(menu_index).err() catch {};
                        cout.queryMode(menu_index, &text_modes.items[menu_index].cols, &text_modes.items[menu_index].rows).err() catch {};
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

fn highlightCursor() void {
    const cout = common.cout;
    cout.setAttribute(EfiColor.green.bg(.green)).err() catch {};
    print(" ");
}

fn printContorls(menu_bottom: usize, menu_top: usize) void {
    const cout = common.cout;

    cout.setCursorPosition(0, menu_bottom - 3).err() catch {};
    print("Up/Down Arrow = Move Cursor\r\nEnter = Select\r\nEscape = Go Back");
    cout.setAttribute(DEFAULT_COLOR).err() catch {};
    cout.setCursorPosition(0, menu_top).err() catch {};
}
