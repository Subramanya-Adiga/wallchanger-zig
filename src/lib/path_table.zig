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

pub fn serialize(self: *Self) !void {
    if (self.modified) {
        const dir = try kf.getPath(self.arena.allocator(), .local_configuration);
        if (dir) |config_dir| {
            const conc_name = try std.fs.path.join(self.arena.allocator(), &[_][]const u8{ config_dir, "wallchanger/libraries/path_table.json" });

            const size = std.mem.replacementSize(u8, conc_name, "/", std.fs.path.sep_str);
            const config_file_name = try self.arena.allocator().alloc(u8, size);
            _ = std.mem.replace(u8, conc_name, "/", std.fs.path.sep_str, config_file_name);

            try std.fs.cwd().makePath(std.fs.path.dirname(config_file_name).?);

            var config_check: bool = false;
            var config_file: std.fs.File = undefined;

            std.fs.accessAbsolute(config_file_name, .{}) catch |err| {
                config_check = if (err == error.FilenotFound) false else true;
            };

            if (config_check) {
                config_file = try std.fs.createFileAbsolute(config_file_name, .{
                    .exclusive = true,
                });
            } else {
                config_file = try std.fs.openFileAbsolute(config_file_name, .{
                    .mode = .write_only,
                });
            }
            defer config_file.close();

            try std.json.stringify(self.path_store.items, .{ .whitespace = .indent_tab }, config_file.writer());
        }
    }
}

pub fn deserialize(self: *Self) !bool {
    const dir = try kf.getPath(self.arena.allocator(), .local_configuration);
    if (dir) |config_dir| {
        const conc_name = try std.fs.path.join(self.arena.allocator(), &[_][]const u8{ config_dir, "wallchanger/libraries/path_table.json" });

        const size = std.mem.replacementSize(u8, conc_name, "/", std.fs.path.sep_str);
        const config_file_name = try self.arena.allocator().alloc(u8, size);
        _ = std.mem.replace(u8, conc_name, "/", std.fs.path.sep_str, config_file_name);

        var table_exists: bool = true;

        std.fs.accessAbsolute(config_file_name, .{}) catch |err| {
            table_exists = if (err == error.FilenotFound) false else true;
        };

        if (table_exists) {
            const config_buf = try std.fs.cwd().readFileAlloc(self.arena.allocator(), config_file_name, 4096);
            const parsed = try std.json.parseFromSlice(@TypeOf(self.path_store.items), self.arena.allocator(), config_buf, .{});
            defer parsed.deinit();
            self.path_store.items = parsed.value;
            return true;
        }
        return false;
    }
    return false;
}
