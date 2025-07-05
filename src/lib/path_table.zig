const std = @import("std");
const kf = @import("known-folders");

const Self = @This();

allocator: std.mem.Allocator = undefined,
path_store: std.ArrayList(PathType) = undefined,
modified: bool = false,

const PathType = struct { id: u32, path: []const u8 };

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
        .path_store = std.ArrayList(PathType).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.modified = false;
}

pub fn insert(self: *Self, path: []const u8) !bool {
    if (std.fs.path.dirname(path)) |has_path| {
        const crc = std.hash.Crc32.hash(has_path);
        const append_type: PathType = .{ .id = crc, .path = path };

        if (self.path_store.capacity == 0) {
            try self.path_store.append(append_type);
            self.modified = true;
        } else {
            for (self.path_store.items) |elem| {
                if (!std.meta.eql(elem, append_type)) {
                    try self.path_store.append(append_type);
                    self.modified = true;
                }
            }
        }

        return true;
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
        var buf = std.mem.zeroes([256]u8);
        var fba = std.heap.FixedBufferAllocator.init(&buf);

        const dir = try kf.getPath(fba.allocator(), .local_configuration);
        if (dir) |config_dir| {
            const conc_name = try std.fs.path.join(fba.allocator(), &[_][]const u8{ config_dir, "wallchanger/libraries/path_table.json" });

            const size = std.mem.replacementSize(u8, conc_name, "/", std.fs.path.sep_str);
            const config_file_name = try fba.allocator().alloc(u8, size);
            _ = std.mem.replace(u8, conc_name, "/", std.fs.path.sep_str, config_file_name);

            try std.fs.cwd().makePath(std.fs.path.dirname(config_file_name).?);

            var config_check: bool = true;
            var config_file: std.fs.File = undefined;

            std.fs.cwd().access(config_file_name, .{}) catch |err| {
                config_check = if (err == error.FileNotFound) false else true;
            };

            if (config_check) {
                config_file = try std.fs.openFileAbsolute(config_file_name, .{
                    .mode = .write_only,
                });
            } else {
                config_file = try std.fs.createFileAbsolute(config_file_name, .{
                    .exclusive = true,
                });
            }
            defer config_file.close();

            try std.json.stringify(self.path_store.items, .{ .whitespace = .indent_tab }, config_file.writer());
        }
    }
}

pub fn deserialize(self: *Self) !bool {
    var buf = std.mem.zeroes([4096]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const dir = try kf.getPath(fba.allocator(), .local_configuration);
    if (dir) |config_dir| {
        const conc_name = try std.fs.path.join(fba.allocator(), &[_][]const u8{ config_dir, "wallchanger/libraries/path_table.json" });

        const size = std.mem.replacementSize(u8, conc_name, "/", std.fs.path.sep_str);
        const config_file_name = try fba.allocator().alloc(u8, size);
        _ = std.mem.replace(u8, conc_name, "/", std.fs.path.sep_str, config_file_name);

        var table_exists: bool = true;

        std.fs.accessAbsolute(config_file_name, .{}) catch |err| {
            table_exists = if (err == error.FilenotFound) false else true;
        };

        if (table_exists) {
            const config_buf = try std.fs.cwd().readFileAlloc(fba.allocator(), config_file_name, 2048);
            const parsed = try std.json.parseFromSlice(@TypeOf(self.path_store.items), self.allocator, config_buf, .{});
            defer parsed.deinit();
            self.path_store.items = parsed.value;
            return true;
        }
        return false;
    }
    return false;
}
