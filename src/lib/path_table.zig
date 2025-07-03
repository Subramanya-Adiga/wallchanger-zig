const std = @import("std");
const kf = @import("known-folders");

const Self = @This();

allocator: std.mem.Allocator = undefined,
arena: std.heap.ArenaAllocator = undefined,
path_store: std.ArrayList(PathType) = undefined,
modified: bool = false,

const PathType = struct { id: u32, path: []const u8 };

pub fn init(allocator: std.mem.Allocator) Self {
    var ret: Self = .{
        .allocator = allocator,
        .arena = std.heap.ArenaAllocator.init(allocator),
    };
    ret.path_store = std.ArrayList(PathType).init(ret.arena.allocator());
    return ret;
}

pub fn deinit(self: *Self) void {
    _ = self.arena.reset(.free_all);
    self.arena.deinit();
    self.modified = false;
}

pub fn insert(self: *Self, path: []const u8) !bool {
    if (std.fs.path.dirname(path)) |has_path| {
        const crc = std.hash.Crc32.hash(has_path);
        const append_type: PathType = .{ .id = crc, .path = path };
        if (std.mem.containsAtLeast(PathType, self.path_store.items, 0, append_type)) {
            try self.path_store.append(append_type);
            return true;
        }
        return false;
    }
    return error.NullPath;
}

pub fn get(self: *Self, id: u32) ?[]const u8 {
    for (self.path_store.items) |ent| {
        if (ent.id == id) {
            return ent.path;
        }
    }
    return null;
}
