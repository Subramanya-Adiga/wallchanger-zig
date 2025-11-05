const std = @import("std");
const kf = @import("known-folders");
const Cache = @import("cache.zig");
const StringTable = @import("string_table.zig");

const Self = @This();

pub const StoreType = struct {
    cache_type: CacheType,
    name: []const u8,
    cache: Cache,
};

pub const CacheType = enum(u8) { Directory, Individual, Mixed };

cache_arena: std.heap.ArenaAllocator = undefined,
store: std.MultiArrayList(StoreType) = .empty,
str_store: StringTable = .{},
current: ?*StoreType = undefined,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .cache_arena = .init(allocator) };
}

pub fn deinit(self: *Self) void {
    self.str_store.deinit(self.cache_arena.allocator());
    self.store.deinit(self.cache_arena.allocator());
    self.current = null;
    self.cache_arena.deinit();
}

pub fn makeCache(self: *Self, name: []const u8, cache_type: CacheType) !bool {
    const pos = self.getPos(name);
    if (pos == null) {
        try self.store.append(self.cache_arena.allocator(), .{
            .name = name,
            .cache = .init(self.cache_arena.allocator()),
            .cache_type = cache_type,
        });
        return true;
    }
    return false;
}

pub fn getCache(self: *Self, name: []const u8) ?*Cache {
    const pos = self.getPos(name);
    if (pos) |loc| {
        return &self.store.items(.cache)[loc];
    }
    return null;
}

fn getPos(self: *Self, name: []const u8) ?usize {
    if (self.store.items(.name).len <= 0) return null;
    for (self.store.items(.name), 0..self.store.len) |elem, i| {
        if (std.mem.eql(u8, elem, name)) {
            return i;
        }
    }
    return null;
}

pub fn serialize(self: *Self) !void {
    var buf = std.mem.zeroes([256]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const config_file = try configFileName(fba.allocator());
    if (config_file) |config_file_name| {
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

        var jw = std.json.writeStream(cache_file.writer(), .{});
        defer jw.deinit();
        try jw.beginObject();
        try jw.objectField("size");
        try jw.write(self.store.len);
        try jw.objectField("store");
        try jw.beginArray();
        for (self.store.items(.cache_type), self.store.items(.name), self.store.items(.cache)) |ctype, name, cache| {
            try jw.write(@as(StoreType, .{ .cache_type = ctype, .name = name, .cache = cache }));
        }
        try jw.endArray();
        try jw.endObject();
    }
    try self.str_store.serialize();
}

pub fn deseraialize(self: *Self) !void {
    var buf = std.mem.zeroes([2048 * 1024]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    _ = try self.str_store.deserialize(self.alloc);

    const config_file = try configFileName(fba.allocator());
    if (config_file) |config_file_name| {
        var cache_exists: bool = true;

        std.fs.accessAbsolute(config_file_name, .{}) catch |err| {
            cache_exists = if (err == error.FilenotFound) false else true;
        };

        if (cache_exists) {
            fba.reset();
            const config_buf = try std.fs.cwd().readFileAlloc(fba.allocator(), config_file_name, 2048 * 1024);
            //Construct JSON Object Scanner
            var parse_arena = std.heap.ArenaAllocator.init(fba.allocator());
            defer parse_arena.deinit();
            const parse_allocator = parse_arena.allocator();

            var source = std.json.Scanner.initCompleteInput(parse_allocator, config_buf);
            defer source.deinit();
            const options: std.json.ParseOptions = .{ .allocate = .alloc_if_needed, .max_value_len = source.input.len };

            std.debug.assert(.object_begin == try source.next());

            const size_field = try std.json.innerParse([]const u8, parse_allocator, &source, options);
            if (std.mem.eql(u8, "size", size_field) == false) {
                return error.UnexpectedField;
            }

            const content_size = try std.json.innerParse(usize, parse_allocator, &source, options);

            const store_field = try std.json.innerParse([]const u8, parse_allocator, &source, options);
            if (std.mem.eql(u8, "store", store_field) == false) {
                return error.UnexpectedField;
            }

            switch (try source.peekNextTokenType()) {
                .array_begin => {
                    std.debug.assert(.array_begin == try source.next());
                    for (0..content_size) |pos| {
                        try self.store.insert(self.cache_arena.allocator(), pos, try std.json.innerParse(StoreType, parse_allocator, &source, options));
                        fba.reset();
                    }
                    std.debug.assert(.array_end == try source.next());
                },
                else => return error.UnexpectedToken,
            }

            std.debug.assert(.object_end == try source.next());

            std.debug.assert(.end_of_document == try source.next());
        }
    }
}

fn configFileName(allocator: std.mem.Allocator) !?[]const u8 {
    const dir = try kf.getPath(allocator, .local_configuration);
    if (dir) |config_dir| {
        const conc_name = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "wallchanger/data/cache.json" });

        try std.fs.cwd().makePath(std.fs.path.dirname(conc_name).?);
        allocator.free(dir.?);

        return conc_name;
    }
    return null;
}

test "CacheLibrary Test" {
    var testing_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer testing_arena.deinit();
    const alloc = testing_arena.allocator();

    var clib: Self = .init(alloc);
    defer clib.deinit();

    const val = try clib.makeCache("Wallpaper", .Directory);
    const val2 = try clib.makeCache("Wallpaper", .Directory);
    const val3 = try clib.makeCache("denise", .Directory);

    try std.testing.expectEqual(val, true);
    try std.testing.expectEqual(val2, false);
    try std.testing.expectEqual(val3, true);

    try std.testing.expectEqual(null, clib.getCache("help"));
}
