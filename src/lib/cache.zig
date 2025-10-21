const std = @import("std");

const Self = @This();

pub const CacheState = enum(u2) {
    Null,
    Unused,
    Used,
    Favorate,
};

store: std.ArrayList(u64) = undefined,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .store = std.ArrayList(u64).init(allocator) };
}

pub fn deinit(self: *Self) void {
    self.store.deinit();
}

pub fn insert(self: *Self, value: u64) !bool {
    if (!self.exists(value)) {
        try self.store.append(value);
        return true;
    }
    return error.CacheValueExists;
}

pub fn getValue(self: *Self, index: usize) !u64 {
    if (index <= self.store.len) {
        return self.store.items[index];
    }
    return error.IndexDoesNotExists;
}

pub fn setValue(self: *Self, index: usize, value: u64) !bool {
    if (index <= self.store.len) {
        self.store.items[index] = value;
        return bool;
    }
    return error.IndexDoesNotExists;
}

pub fn getState(self: *Self, index: usize) !CacheState {
    if (index <= self.store.len) {
        return @enumFromInt(@as(u2, @truncate(self.store.items[index])));
    }
    return error.IndexDoesNotExists;
}

pub fn setState(self: *Self, index: usize, state: CacheState) !bool {
    if (index <= self.store.len) {
        var val = self.store.items[index];
        val = (val >> 2) << 2;
        val |= @intFromEnum(state);
        self.store.items[index] = val;
        return true;
    }
    return error.IndexDoesNotExists;
}

pub fn jsonStringify(self: *const Self, jw: anytype) !void {
    try jw.beginObject();
    try jw.objectField("size");
    try jw.write(self.store.items.len);
    try jw.objectField("store");
    // try jw.beginArray();
    try jw.write(self.store.items);
    // try jw.endArray();
    try jw.endObject();
}

pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    var buf = std.mem.zeroes([2048]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    var ret: Self = .{ .store = std.ArrayList(u64).init(allocator) };

    const size_field = try std.json.innerParse([]const u8, fba.allocator(), source, options);
    if (std.mem.eql(u8, size_field, "size") == false) {
        return error.UnknownField;
    }

    const size = try std.json.innerParse(usize, fba.allocator(), source, options);
    try ret.store.ensureTotalCapacity(size);

    const value_field = try std.json.innerParse([]const u8, fba.allocator(), source, options);
    if (std.mem.eql(u8, value_field, "store") == false) {
        return error.UnknownField;
    }

    switch (try source.peekNextTokenType()) {
        .array_begin => {
            std.debug.assert(.array_begin == try source.next());
            for (0..size) |_| {
                fba.reset();
                try ret.store.append(try std.json.innerParse(u64, fba.allocator(), source, options));
            }
            std.debug.assert(.array_end == try source.next());
        },
        else => {},
    }

    if (try source.next() != .object_end) {
        return error.UnexpectedToken;
    }

    return ret;
}

fn exists(self: *Self, cache_value: u64) bool {
    for (self.store.items) |itm| {
        if ((itm >> 2) == (cache_value >> 2)) {
            return true;
        }
    }
    return false;
}

test "Cache Stringify And Parse" {
    var cache = Self.init(std.testing.allocator);
    _ = try cache.insert(55);
    _ = try cache.insert(66);
    _ = try cache.insert(77);

    var cachestr = std.ArrayList(u8).init(std.testing.allocator);

    try std.json.stringify(cache, .{}, cachestr.writer());
    std.debug.print("{s}\n", .{cachestr.items});

    var cache2 = Self.init(std.testing.allocator);

    const parsed = try std.json.parseFromSlice(Self, std.testing.allocator, cachestr.items, .{});
    cache2 = parsed.value;

    for (cache2.store.items) |val| {
        std.debug.print("{}\n", .{val});
    }
}
