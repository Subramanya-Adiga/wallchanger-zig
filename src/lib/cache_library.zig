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

allocator: std.mem.Allocator = undefined,
store: std.MultiArrayList(StoreType) = .{},

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Self) void {
    self.store.deinit(self.allocator);
}

pub fn insert(self: *Self, name: []const u8, cache: Cache) !void {
    try self.store.append(self.allocator, .{ .name = name, .cache = cache, .cache_type = .Directory });
}

pub fn serialize(self: *Self) !void {
    var buf = std.mem.zeroes([256]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const dir = try kf.getPath(fba.allocator(), .local_configuration);
    if (dir) |config_dir| {
        const conc_name = try std.fs.path.join(fba.allocator(), &[_][]const u8{ config_dir, "wallchanger/data/cache.json" });

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
}

pub fn deseraialize(self: *Self) !void {
    var buf = std.mem.zeroes([2048 * 1024]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const dir = try kf.getPath(fba.allocator(), .local_configuration);
    if (dir) |config_dir| {
        const conc_name = try std.fs.path.join(fba.allocator(), &[_][]const u8{ config_dir, "wallchanger/data/cache.json" });

        const size = std.mem.replacementSize(u8, conc_name, "/", std.fs.path.sep_str);
        const config_file_name = try fba.allocator().alloc(u8, size);
        _ = std.mem.replace(u8, conc_name, "/", std.fs.path.sep_str, config_file_name);

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
                        try self.store.insert(self.allocator, pos, try std.json.innerParse(StoreType, parse_allocator, &source, options));
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
