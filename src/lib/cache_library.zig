const std = @import("std");
const kf = @import("known-folders");
const Cache = @import("cache.zig");

const Self = @This();

pub const StoreType = struct {
    cache_type: CacheType,
    name: []const u8,
    cache: Cache,
};

pub const CacheType = enum(u8) { Directory, Individual, Mixed };

pub const ContainsReturnType = struct {
    exists: bool,
    pos: usize,
};

cache_arena: std.heap.ArenaAllocator = undefined,
store: std.MultiArrayList(StoreType) = .{},
current: ?*StoreType = undefined,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .cache_arena = std.heap.ArenaAllocator.init(allocator) };
}

pub fn deinit(self: *Self) void {
    self.store.deinit(self.cache_arena.allocator());
    self.cache_arena.deinit();
}

pub fn insert(self: *Self, name: []const u8, cache: Cache) !void {
    if (self.contains(name).exists == false) {
        try self.store.append(self.cache_arena.allocator(), .{ .name = name, .cache = cache, .cache_type = .Directory });
    }
}

pub fn contains(self: *Self, name: []const u8) ContainsReturnType {
    for (self.store.items(.name), 0..self.store.len) |elem, i| {
        if (std.mem.eql(u8, elem, name)) {
            return .{ .exists = true, .pos = i };
        }
    }
    return .{ .exists = false, .pos = 0 };
}

pub fn getCache(self: *Self, name: []const u8) ?*Cache {
    const pred = self.contains(name);
    if (pred.exists) {
        return &self.store.items(.cache)[pred.pos];
    }
    return null;
}

pub fn putCache(self: *Self, name: []const u8, cache: Cache) !void {
    const pred = self.contains(name);
    if (pred.exists) {
        self.store.orderedRemove(pred.pos);
        try self.store.append(self.cache_arena.allocator(), cache);
    }
    return error.CacheDoesNotExists;
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
}

pub fn deseraialize(self: *Self) !void {
    var buf = std.mem.zeroes([2048 * 1024]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

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

        const size = std.mem.replacementSize(u8, conc_name, "/", std.fs.path.sep_str);
        const config_file_name = try allocator.alloc(u8, size);
        _ = std.mem.replace(u8, conc_name, "/", std.fs.path.sep_str, config_file_name);

        try std.fs.cwd().makePath(std.fs.path.dirname(config_file_name).?);
        allocator.free(dir.?);
        return config_file_name;
    }
    return null;
}
