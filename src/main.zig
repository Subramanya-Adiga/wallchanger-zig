const std = @import("std");

pub fn main(init: std.process.Init) !void {
    _ = init;
    std.debug.print("Hello World!\n", .{});
}

test "CacheValueSetting" {
    const path_id = "D:/wallpaper";
    const name_id = "499p.jpg";

    const crc_path = std.hash.crc.Crc30Cdma.hash(path_id);
    const crc_name = std.hash.Crc32.hash(name_id);

    var combined: u64 = 0;
    combined |= crc_path;
    combined <<= 32;
    combined |= crc_name;
    combined <<= 2;
    combined |= 3;

    std.debug.print("path_crc:{}\nname_crc:{}\ncrc_combined:{}\n", .{ crc_path, crc_name, combined });
    std.debug.print("path_crc_bin:{b}\nname_crc_bin:{b}\ncrc_combined:{b}\n", .{ crc_path, crc_name, combined });

    const path_pull = (combined >> 34);
    const name_pull = ((combined >> 2) & 0xFFFFFFFF);
    const state_pull: u2 = @truncate(combined);
    std.debug.print("path_crc:{}\nname_crc:{}\nstate:{}\n", .{ path_pull, name_pull, state_pull });
}
