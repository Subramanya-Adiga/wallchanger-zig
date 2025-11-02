const std = @import("std");
const kf = @import("known-folders");

const Self = @This();

table_store: std.MultiArrayList(TableType) = .{},

const TableType = struct { id: u32, str: []const u8 };

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.table_store.deinit(allocator);
}

pub fn insert(self: *Self, allocator: std.mem.Allocator, id: u32, str: []const u8) !bool {
    if (std.mem.containsAtLeast(u32, self.table_store.items(.id), 1, &[_]u32{id}) == false) {
        try self.table_store.append(allocator, .{ .id = id, .str = str });
        return true;
    }
    return false;
}

pub fn get(self: *Self, id: u32) ?[]const u8 {
    const pos = std.mem.indexOf(u32, self.table_store.items(.id), &[_]u32{id});
    if (pos) |i| {
        return self.table_store.get(i).str;
    }
    return null;
}

pub fn serialize(self: *Self) !void {
    var buf = std.mem.zeroes([256]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const file_name = try strTableFile(fba.allocator());
    if (file_name) |config_file_name| {
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

        var jw = std.json.writeStream(config_file.writer(), .{});
        defer jw.deinit();
        try jw.beginObject();
        try jw.objectField("size");
        try jw.write(self.table_store.len);
        try jw.objectField("store");
        try jw.beginArray();
        for (self.table_store.items(.id), self.table_store.items(.str)) |i, s| {
            try jw.write(@as(TableType, .{ .id = i, .str = s }));
        }
        try jw.endArray();
        try jw.endObject();
    }
}

pub fn deserialize(self: *Self, allocator: std.mem.Allocator) !bool {
    var buf = std.mem.zeroes([2048 * 1024]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const config_file = try strTableFile(fba.allocator());
    if (config_file) |config_file_name| {
        var table_exists: bool = true;

        std.fs.accessAbsolute(config_file_name, .{}) catch |err| {
            table_exists = if (err == error.FilenotFound) false else true;
        };

        if (table_exists) {
            fba.reset();
            const config_buf = try std.fs.cwd().readFileAlloc(fba.allocator(), config_file_name, 2048 * 1024);

            var parse_arena = std.heap.ArenaAllocator.init(fba.allocator());
            defer parse_arena.deinit();
            const parse_allocator = parse_arena.allocator();

            var source = std.json.Scanner.initCompleteInput(parse_allocator, config_buf);
            defer source.deinit();
            const opts: std.json.ParseOptions = .{ .allocate = .alloc_if_needed, .max_value_len = source.input.len };

            std.debug.assert(.object_begin == try source.next());

            const size_field = try std.json.innerParse([]const u8, parse_allocator, &source, opts);
            if (std.mem.eql(u8, "size", size_field) == false) {
                return error.unknownfield;
            }
            const content_size = try std.json.innerParse(usize, parse_allocator, &source, opts);

            try self.table_store.ensureTotalCapacity(allocator, content_size);

            const store_field = try std.json.innerParse([]const u8, parse_allocator, &source, opts);
            if (std.mem.eql(u8, "store", store_field) == false) {
                return error.unknownfield;
            }

            switch (try source.peekNextTokenType()) {
                .array_begin => {
                    std.debug.assert(.array_begin == try source.next());
                    for (0..content_size) |idx| {
                        try self.table_store.insert(allocator, idx, try std.json.innerParse(TableType, parse_allocator, &source, opts));
                        fba.reset();
                    }
                    std.debug.assert(.array_end == try source.next());
                },
                else => return error.UnexpectedToken,
            }

            std.debug.assert(.object_end == try source.next());
            std.debug.assert(.end_of_document == try source.next());

            return true;
        }
        return false;
    }
    return false;
}

fn strTableFile(allocator: std.mem.Allocator) !?[]const u8 {
    const dir = try kf.getPath(allocator, .local_configuration);
    if (dir) |config_dir| {
        const conc_name = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "wallchanger/data/str_table.json" });

        try std.fs.cwd().makePath(std.fs.path.dirname(conc_name).?);
        allocator.free(dir.?);
        return conc_name;
    }
    return null;
}

test "String Table Insertion" {
    const builtin = @import("builtin");
    var testing_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer testing_arena.deinit();
    const alloc = testing_arena.allocator();

    const path = switch (builtin.os.tag) {
        .windows => blk: {
            const doc_path = try kf.getPath(alloc, .home);
            const doc_conc = try std.fs.path.join(alloc, &[_][]const u8{ doc_path.?, "\\Documents\\wall" });
            var dir_check: bool = true;
            std.fs.cwd().access(doc_conc, .{}) catch |err| {
                dir_check = if (err == error.FileNotFound) false else true;
            };
            break :blk if (dir_check) doc_conc else "D:/Wallpaper";
        },
        .linux => blk: {
            const wall_path = try kf.getPath(alloc, .home);
            const wall_conc = try std.fs.path.join(alloc, &[_][]const u8{ wall_path.?, "newMass/Wallpaper" });
            break :blk wall_conc;
        },
        else => std.debug.assert(false),
    };

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var walk = dir.iterate();

    var str_table: Self = .{};
    defer str_table.deinit(alloc);

    while (try walk.next()) |elem| {
        if (elem.kind == .file) {
            const id = std.hash.Crc32.hash(elem.name);
            try std.testing.expectEqual(try str_table.insert(alloc, id, try std.fmt.allocPrint(alloc, "{s}", .{elem.name})), true);
        }
    }
}
