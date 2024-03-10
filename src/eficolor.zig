pub const DEFAULT_COLOR: usize = EfiColor.white.bg(EfiColor.blue);
pub const HIGHLIGHT_COLOR: usize = EfiColor.blue.bg(EfiColor.light_gray);

pub const EfiColor = enum(usize) {
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
