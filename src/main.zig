const std = @import("std");
const patht = @import("changer").StrTable;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var path: patht = .{};
    defer path.deinit(arena.allocator());

    var dir = try std.fs.cwd().openDir("C:/Users/subbu/Documents/wall/", .{ .iterate = true });
    defer dir.close();

    var walk = try dir.walk(arena.allocator());
    defer walk.deinit();

    while (try walk.next()) |elem| {
        _ = try path.insert(arena.allocator(), try std.fmt.allocPrint(arena.allocator(), "{s}", .{elem.path}));
    }
    try path.serialize();

    for (path.table_store.items(.id), path.table_store.items(.str)) |i, s| {
        std.debug.print("{} {s}\n", .{ i, s });
    }
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
