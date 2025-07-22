//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const patht = @import("changer").PathTable;
const cache = @import("changer").Cache;
const clib = @import("changer").CacheLibrary;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var path = patht.init(arena.allocator());
    defer path.deinit();
    _ = try path.insert("C:/Users/subbu/Documents/wall");
    _ = try path.insert("C:/Users/subbu/Documents");
    try path.serialize();
    // _ = try path.deserialize();
    // std.debug.print("{any}\n", .{path.path_store.items});
    for (path.path_store.items) |elem| {
        std.debug.print("{} {s}\n", .{ elem.id, elem.path });
    }

    var cache_1: cache = .{};
    defer cache_1.deinit(arena.allocator());

    _ = try cache_1.insert(arena.allocator(), 0);
    _ = try cache_1.insert(arena.allocator(), 1);
    _ = try cache_1.insert(arena.allocator(), 3);
    _ = try cache_1.insert(arena.allocator(), 4);

    var file = try std.fs.cwd().createFile("test.json", .{});
    defer file.close();

    try std.json.stringify(cache_1, .{}, file.writer());

    const path_id = "D:/wallpaper";
    const name_id = "499p.jpg";

    const path_crc = std.hash.Crc32.hash(path_id);
    const name_crc = std.hash.Crc32.hash(name_id);

    var combined_hash: u64 = path_crc;
    combined_hash <<= 32;
    combined_hash |= name_crc;

    const path_pull = (combined_hash >> 32);
    const name_pull = (combined_hash & 0xFFFFFFFF);
    // const unset = path_pull & @as(u32, (~@as(u32, (1 << 1))));
    std.debug.print("{} {} {} {b} {} {b}\n", .{ path_crc, name_crc, combined_hash, path_pull, name_pull, @as(u2, @truncate(path_pull)) });

    const buf = try std.fs.cwd().readFileAlloc(gpa.allocator(), "test.json", 4096);
    defer gpa.allocator().free(buf);
    const cache_2 = try std.json.parseFromSlice(cache, gpa.allocator(), buf, .{});
    defer cache_2.deinit();

    for (cache_2.value.store.items(.value)) |elem| {
        std.debug.print("value:{}\n", .{elem});
    }
    std.debug.print("{} {}\n", .{ @sizeOf(cache), @alignOf(cache) });
    var crc30: u32 = 0;
    crc30 = std.hash.crc.Crc30Cdma.hash(path_id);
    crc30 <<= 2;
    std.debug.print("{} {}\n {b}\n {b}\n {}\n {b}\n {}\n {b}\n {b}\n", .{ crc30, (crc30 >> 2), crc30, std.hash.crc.Crc30Cdma.hash(path_id), crc30 | (@as(u2, 0)), crc30 | (@as(u2, 0)), @as(u2, @truncate(crc30 | (@as(u2, 0)))), @as(u2, @truncate(crc30 | (@as(u2, 0)))), (crc30 + 0) & 0x01 });

    var stat: u2 = 0;
    stat |= ~@as(u2, (0 << 1));
    stat |= ~@as(u2, (1 << 1));

    var stat2: u2 = 0;
    stat2 |= @as(u2, (1 << 1));
    std.debug.print("state:{b} {} {b} {b}\n stat2:{b} {} {b} {b}\n", .{ stat, stat, stat & 0x1, stat & 0x2, stat2, stat2, stat2 & 0x1, stat2 & 0x2 });
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "use other module" {
    try std.testing.expectEqual(@as(i32, 150), lib.add(100, 50));
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("wallchanger_lib");
