const std = @import("std");

const Self = @This();

store: std.MultiArrayList(CacheType) = .{},

const CacheType = struct { value: u64, state: u2 };

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.store.deinit(allocator);
}

pub fn insert(self: *Self, allocator: std.mem.Allocator, value: u64) !bool {
    if (!self.exists(value)) {
        try self.store.append(allocator, .{ .value = value, .state = 0 });
        return true;
    }
    return error.CacheValueExists;
}

pub fn getValue(self: *Self, index: usize) !u64 {
    if (index <= self.store.len) {
        var val = self.store.get(index);
        val.state = 1;
        self.store.set(index, val);
        return val.value;
    }
    return error.IndexDoesNotExists;
}

pub fn setValue(self: *Self, index: usize, value: u64) !bool {
    if (index <= self.store.len) {
        var val = self.store.get(index);
        val.value = value;
        self.store.set(index, val);
        return bool;
    }
    return error.IndexDoesNotExists;
}

pub fn getState(self: *Self, index: usize) !u2 {
    if (index <= self.store.len) {
        return self.store.get(index).state;
    }
    return error.IndexDoesNotExists;
}

pub fn setState(self: *Self, index: usize, state: u2) !bool {
    if (index <= self.store.len) {
        var val = self.store.get(index);
        val.state = state;
        self.store.set(index, val);
        return true;
    }
    return error.IndexDoesNotExists;
}

pub fn jsonStringify(self: *const Self, jw: anytype) !void {
    try jw.beginObject();
    try jw.objectField("size");
    try jw.write(self.store.len);
    try jw.objectField("store");
    try jw.beginArray();
    for (self.store.items(.value), self.store.items(.state)) |elem, stat| {
        try jw.write(@as(CacheType, .{ .value = elem, .state = stat }));
    }
    try jw.endArray();
    try jw.endObject();
}

pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    var buf = std.mem.zeroes([2048]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    var ret: Self = .{ .store = .{} };

    const size_field = try std.json.innerParse([]const u8, fba.allocator(), source, options);
    if (std.mem.eql(u8, size_field, "size") == false) {
        return error.UnknownField;
    }

    const size = try std.json.innerParse(usize, fba.allocator(), source, options);
    try ret.store.ensureTotalCapacity(allocator, size);

    const value_field = try std.json.innerParse([]const u8, fba.allocator(), source, options);
    if (std.mem.eql(u8, value_field, "store") == false) {
        return error.UnknownField;
    }

    switch (try source.peekNextTokenType()) {
        .array_begin => {
            std.debug.assert(.array_begin == try source.next());
            for (0..size) |pos| {
                fba.reset();
                try ret.store.insert(allocator, pos, try std.json.innerParse(CacheType, fba.allocator(), source, options));
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

inline fn exists(self: *Self, cache_value: u64) bool {
    return std.mem.containsAtLeast(u64, self.store.items(.value), 1, &[_]u64{cache_value});
}
