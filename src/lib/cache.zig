const std = @import("std");

const Self = @This();

pub const CacheState = enum(u2) {
    Null,
    Unused,
    Used,
    Favorate,
};

store: std.ArrayList(u64) = .empty,
alloc: std.mem.Allocator = undefined,

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .alloc = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.store.deinit(self.alloc);
}

pub fn insert(self: *Self, value: u64) !bool {
    if (!self.exists(value)) {
        try self.store.append(self.alloc, value);
        return true;
    }
    return error.CacheValueExists;
}

pub fn getValue(self: *Self, index: usize) !u64 {
    if (index <= self.store.items.len) {
        return self.store.items[index];
    }
    return error.IndexDoesNotExists;
}

pub fn setValue(self: *Self, index: usize, value: u64) !bool {
    if (index <= self.store.items.len) {
        self.store.items[index] = value;
        return true;
    }
    return error.IndexDoesNotExists;
}

pub fn getState(self: *Self, index: usize) !CacheState {
    if (index <= self.store.items.len) {
        return @enumFromInt(@as(u2, @truncate(self.store.items[index])));
    }
    return error.IndexDoesNotExists;
}

pub fn setState(self: *Self, index: usize, state: CacheState) !bool {
    if (index <= self.store.items.len) {
        var val = self.store.items[index];
        val = (val >> 2) << 2;
        val |= @intFromEnum(state);
        self.store.items[index] = val;
        return true;
    }
    return error.IndexDoesNotExists;
}

pub fn removeNull(self: *Self) !void {
    var buf = std.mem.zeroes([2048 * 128]u8);
    var fba = std.heap.FixedBufferAllocator(&buf);

    var indecies = std.ArrayList(usize).init(fba.allocator());
    defer indecies.deinit();

    for (self.store.items, 0..self.store.items.len) |val, pos| {
        if (@as(u2, @truncate(val)) == @intFromEnum(CacheState.Null)) {
            try indecies.append(pos);
        }
    }
    self.store.orderedRemoveMany(indecies.items);
}

pub fn jsonStringify(self: *const Self, jw: anytype) !void {
    try jw.beginObject();
    try jw.objectField("size");
    try jw.write(self.store.items.len);
    try jw.objectField("store");
    try jw.write(self.store.items);
    try jw.endObject();
}

pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
    if (try source.next() != .object_begin) {
        return error.UnexpectedToken;
    }

    var buf = std.mem.zeroes([2048]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    var ret: Self = .{
        .alloc = allocator,
    };

    const size_field = try std.json.innerParse([]const u8, fba.allocator(), source, options);
    if (std.mem.eql(u8, size_field, "size") == false) {
        return error.UnknownField;
    }

    const size = try std.json.innerParse(usize, fba.allocator(), source, options);
    try ret.store.ensureTotalCapacity(ret.alloc, size);

    const value_field = try std.json.innerParse([]const u8, fba.allocator(), source, options);
    if (std.mem.eql(u8, value_field, "store") == false) {
        return error.UnknownField;
    }

    try ret.store.appendSlice(ret.alloc, try std.json.innerParse([]u64, allocator, source, options));

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
    const alloc = std.testing.allocator;
    var cache = Self.init(alloc);
    defer cache.deinit();
    _ = try cache.insert(55);
    _ = try cache.insert(66);
    _ = try cache.insert(77);

    var cachestr: std.ArrayList(u8) = .empty;
    defer cachestr.deinit(alloc);

    try cachestr.print(alloc, "{f}", .{std.json.fmt(cache, .{})});

    var cache2 = Self.init(alloc);
    defer cache2.deinit();

    const parsed = try std.json.parseFromSlice(Self, alloc, cachestr.items, .{});
    try cache2.store.appendSlice(cache2.alloc, parsed.value.store.items);
    parsed.deinit();

    try std.testing.expectEqual(cache.store.items.len, cache2.store.items.len);
    try std.testing.expectEqualSlices(u64, cache.store.items, cache2.store.items);
}

test "Cache State Set And Get" {
    const alloc = std.testing.allocator;
    var cache = Self.init(alloc);
    defer cache.deinit();

    _ = try cache.insert(10119347595071929548);

    const state_null = cache.getState(0);
    try std.testing.expectEqual(state_null, CacheState.Null);

    _ = try cache.setState(0, .Used);
    const cache_val_used = try cache.getValue(0);
    const state_used = try cache.getState(0);

    try std.testing.expectEqual(cache_val_used, 10119347595071929550);
    try std.testing.expectEqual(state_used, CacheState.Used);

    _ = try cache.setState(0, .Unused);
    const cache_val_unused = try cache.getValue(0);
    const state_unused = try cache.getState(0);

    try std.testing.expectEqual(cache_val_unused, 10119347595071929549);
    try std.testing.expectEqual(state_unused, CacheState.Unused);

    _ = try cache.setState(0, .Favorate);
    const cache_val_fav = try cache.getValue(0);
    const state_fav = try cache.getState(0);

    try std.testing.expectEqual(cache_val_fav, 10119347595071929551);
    try std.testing.expectEqual(state_fav, CacheState.Favorate);
}
