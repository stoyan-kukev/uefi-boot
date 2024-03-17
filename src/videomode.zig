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

fn highlightCursor() void {
    const cout = common.cout;
    cout.setAttribute(EfiColor.green.bg(.green)).err() catch {};
    print(" ");
}

const GraphicsInfo = uefi.protocol.GraphicsOutput.Mode.Info;

pub fn setVideoMode(alloc: std.mem.Allocator) uefi.Status {
    const cout = common.cout;
    const gop = common.gop;

    cout.clearScreen().err() catch {};

    var size_of_info: usize = undefined;
    var video_modes = std.mem.zeroes([30]GraphicsInfo);
    gop.queryMode(0, &size_of_info, @alignCast(@ptrCast(&video_modes))).err() catch {};
    printArgs(
        alloc,
        "version: {}\r\nhor_res: {}\r\nver_res: {}\r\npix_fmt: {}\r\npix_inf: {}\r\nppsl: {}\r\n",
        .{
            video_modes[0].version,
            video_modes[0].horizontal_resolution,
            video_modes[0].vertical_resolution,
            video_modes[0].pixel_format,
            video_modes[0].pixel_information,
            video_modes[0].pixels_per_scan_line,
        },
    );

    // while (true) {
    //     cout.clearScreen().err() catch {};

    //     print("Text mode information\r\n\r\n");
    //     var max_cols: usize = undefined;
    //     var max_rows: usize = undefined;

    //     cout.queryMode(cout.mode.mode, &max_cols, &max_rows).err() catch {};

    //     printArgs(
    //         alloc,
    //         "Max Mode: {}\r\nCurrent Mode: {}\r\nAttribute: {}\r\nCursor Column: {}\r\nCursor Row: {}\r\nCursor Visible: {}\r\nColumns: {}\r\nRows: {}\r\n",
    //         .{
    //             cout.mode.max_mode,
    //             cout.mode.mode,
    //             cout.mode.attribute,
    //             cout.mode.cursor_column,
    //             cout.mode.cursor_row,
    //             cout.mode.cursor_visible,
    //             max_cols,
    //             max_rows,
    //         },
    //     );

    //     print("\r\nAvailable text modes:\r\n");

    //     const menu_top: usize = @intCast(cout.mode.cursor_row);
    //     var menu_bottom = max_rows;

    //     cout.setCursorPosition(0, menu_bottom - 3).err() catch {};
    //     print("Up/Down Arrow = Move Cursor\r\nEnter = Select\r\nEscape = Go Back");

    //     cout.setCursorPosition(0, menu_top).err() catch {};

    //     menu_bottom -= 4;
    //     const menu_len = menu_bottom - menu_top;

    //     for (&text_modes, 0..) |*text_mode, i| {
    //         cout.queryMode(i, &text_mode.cols, &text_mode.rows).err() catch {};
    //     }

    //     cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};
    //     printArgs(alloc, "Mode 0: {}x{}\r\n", .{ text_modes[0].cols, text_modes[0].rows });

    //     cout.setAttribute(DEFAULT_COLOR).err() catch {};
    //     for (1..menu_len + 1) |i| {
    //         printArgs(alloc, "Mode {}: {}x{}\r\n", .{ i, text_modes[i].cols, text_modes[i].rows });
    //     }

    //     cout.setCursorPosition(0, menu_top).err() catch {};

    //     var menu_index: usize = 0;
    //     var getting_input = true;
    //     var current_row: usize = @intCast(cout.mode.cursor_row);
    //     while (getting_input) {
    //         const key = getKey();
    //         switch (key.input.scan_code) {
    //             ESC_KEY => return uefi.Status.Success,
    //             UP_ARROW => {
    //                 if (current_row >= menu_top and menu_index > 0) {
    //                     cout.setAttribute(DEFAULT_COLOR).err() catch {};

    //                     print("                                \r\n");
    //                     cout.setCursorPosition(0, current_row).err() catch {};
    //                     printArgs(alloc, "Mode {}: {}x{}\r\n", .{
    //                         menu_index,
    //                         text_modes[menu_index].cols,
    //                         text_modes[menu_index].rows,
    //                     });

    //                     menu_index -= 1;
    //                     current_row -= 1;
    //                     cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};

    //                     cout.setCursorPosition(0, current_row).err() catch {};
    //                     print("                                \r\n");

    //                     cout.setCursorPosition(0, current_row).err() catch {};
    //                     printArgs(alloc, "Mode {}: {}x{}\r\n", .{
    //                         menu_index,
    //                         text_modes[menu_index].cols,
    //                         text_modes[menu_index].rows,
    //                     });
    //                 }
    //             },

    //             DOWN_ARROW => {
    //                 if (current_row <= menu_bottom and menu_index < menu_len) {
    //                     cout.setAttribute(DEFAULT_COLOR).err() catch {};

    //                     print("                                \r\n");
    //                     cout.setCursorPosition(0, current_row).err() catch {};
    //                     printArgs(alloc, "Mode {}: {}x{}\r\n", .{
    //                         menu_index,
    //                         text_modes[menu_index].cols,
    //                         text_modes[menu_index].rows,
    //                     });

    //                     menu_index += 1;
    //                     current_row += 1;
    //                     cout.setAttribute(HIGHLIGHT_COLOR).err() catch {};

    //                     // cout.setCursorPosition(0, current_row).err() catch {};
    //                     // print("                                \r\n");

    //                     cout.setCursorPosition(0, current_row).err() catch {};
    //                     printArgs(alloc, "Mode {}: {}x{}\r\n", .{
    //                         menu_index,
    //                         text_modes[menu_index].cols,
    //                         text_modes[menu_index].rows,
    //                     });
    //                 }
    //             },
    //             else => {
    //                 if (key.input.unicode_char == 13 and text_modes[menu_index].cols != 0) {
    //                     cout.setMode(menu_index).err() catch {};
    //                     cout.queryMode(menu_index, &text_modes[menu_index].cols, &text_modes[menu_index].rows).err() catch {};
    //                     cout.clearScreen().err() catch {};

    //                     getting_input = false;
    //                     menu_index = 0;
    //                 }
    //                 break;
    //             },
    //         }
    //     }

    hang();

    return uefi.Status.Success;
    // }
}
