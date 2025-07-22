const std = @import("std");
const kf = @import("known-folders");
const Cache = @import("cache.zig");

const Self = @This();

pub const StoreType = struct {
    cache_type: CacheType,
    name: []const u8,
    cache: Cache,
};

const CacheType = enum { Directory, Individual };

arena: std.heap.ArenaAllocator = undefined,
store: std.MultiArrayList(StoreType) = .{},

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
}

pub fn deinit(self: *Self) void {
    self.store.deinit(self.arena.allocator());
}

pub fn serialize(self: *Self) !void {
    var buf = std.mem.zeroes([256]u8);
    var fba = std.heap.FixedBufferAllocator(&buf);

    const dir = try kf.getPath(fba.allocator(), .local_configuration);
    if (dir) |config_dir| {
        const conc_name = try std.fs.path.join(fba.allocator(), &[_][]const u8{ config_dir, "wallchanger/libraries/cache.json" });

        const size = std.mem.replacementSize(u8, conc_name, "/", std.fs.path.sep_str);
        const config_file_name = try fba.allocator().alloc(u8, size);
        _ = std.mem.replace(u8, conc_name, "/", std.fs.path.sep_str, config_file_name);

        try std.fs.cwd().makePath(std.fs.path.dirname(config_file_name).?);

        var cache_check: bool = true;
        var cache_file: std.fs.File = undefined;

        std.fs.cwd().access(config_file_name, .{}) catch |err| {
            cache_check = if (err == error.FileNotFound) false else true;
        };

        if (cache_check) {
            cache_file = try std.fs.openFileAbsolute(config_file_name, .{
                .mode = .write_only,
            });
        } else {
            cache_file = try std.fs.createFileAbsolute(config_file_name, .{
                .exclusive = true,
            });
        }
        defer cache_file.close();
        try std.json.stringify(self.store.items, .{}, cache_file.writer());
    }
}

pub fn deseraialize(self: *Self) !void {
    var buf = std.mem.zeroes([4096 * 1024]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const dir = try kf.getPath(fba.allocator(), .local_configuration);
    if (dir) |config_dir| {
        const conc_name = try std.fs.path.join(fba.allocator(), &[_][]const u8{ config_dir, "wallchanger/libraries/cache.json" });

        const size = std.mem.replacementSize(u8, conc_name, "/", std.fs.path.sep_str);
        const config_file_name = try fba.allocator().alloc(u8, size);
        _ = std.mem.replace(u8, conc_name, "/", std.fs.path.sep_str, config_file_name);

        var cache_exists: bool = true;

        std.fs.accessAbsolute(config_file_name, .{}) catch |err| {
            cache_exists = if (err == error.FilenotFound) false else true;
        };

        if (cache_exists) {
            const config_buf = try std.fs.cwd().readFileAlloc(fba.allocator(), config_file_name, 3072 * 1024);
            const parsed = try std.json.parseFromSlice(@TypeOf(self.path_store.items), self.allocator, config_buf, .{});
            defer parsed.deinit();
            self.path_store.items = parsed.value;
        }
    }
}
