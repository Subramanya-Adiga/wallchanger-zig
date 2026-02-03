const std = @import("std");
const IO = std.Io;
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

pub fn serialize(self: *Self, io: IO, envMap: *std.process.Environ.Map) !void {
    var buf = std.mem.zeroes([256]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const file_name = try strTableFile(fba.allocator(), io, envMap);
    if (file_name) |config_file_name| {
        var config_check: bool = true;
        var config_file: IO.File = undefined;

        IO.Dir.cwd().access(io, config_file_name, .{}) catch |err| {
            config_check = if (err == error.FileNotFound) false else true;
        };

        if (config_check) {
            config_file = try IO.Dir.openFileAbsolute(io, config_file_name, .{
                .mode = .write_only,
            });
        } else {
            config_file = try IO.Dir.createFileAbsolute(io, config_file_name, .{
                .exclusive = true,
            });
        }
        defer IO.File.close(config_file, io);

        var config_writer_buf = std.mem.zeroes([1024]u8);
        var config_file_writer = config_file.writer(io, &config_writer_buf);
        const file_writer = &config_file_writer.interface;

        var jw: std.json.Stringify = .{
            .writer = file_writer,
        };
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

        try file_writer.flush();
    }
}

pub fn deserialize(self: *Self, allocator: std.mem.Allocator, io: IO, envMap: *std.process.Environ.Map) !bool {
    var buf = std.mem.zeroes([2048 * 1024]u8);
    var fba = std.heap.FixedBufferAllocator.init(&buf);

    const config_file = try strTableFile(fba.allocator(), io, envMap);
    if (config_file) |config_file_name| {
        var table_exists: bool = true;

        IO.Dir.accessAbsolute(io, config_file_name, .{}) catch |err| {
            table_exists = if (err == error.FilenotFound) false else true;
        };

        if (table_exists) {
            fba.reset();
            const config_buf = try IO.Dir.cwd().readFileAlloc(io, config_file_name, fba.allocator(), .limited64(2048 * 1024));

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
    unreachable;
}

fn strTableFile(allocator: std.mem.Allocator, io: IO, envMap: *std.process.Environ.Map) !?[]const u8 {
    const dir = try kf.getPath(io, allocator, envMap.*, .local_configuration);
    if (dir) |config_dir| {
        const conc_name = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "wallchanger/data/str_table.json" });

        try IO.Dir.cwd().createDirPath(io, std.fs.path.dirname(conc_name).?);
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
    const io = std.testing.io;
    var env = try std.testing.io_instance.environ.process_environ.createMap(alloc);
    defer env.deinit();

    const path = switch (builtin.os.tag) {
        .windows => blk: {
            const doc_path = try kf.getPath(io, alloc, env, .home);
            const doc_conc = try std.fs.path.join(alloc, &[_][]const u8{ doc_path.?, "\\Documents\\wall" });
            var dir_check: bool = true;
            IO.Dir.cwd().access(io, doc_conc, .{}) catch |err| {
                dir_check = if (err == error.FileNotFound) false else true;
            };
            break :blk if (dir_check) doc_conc else "D:/Wallpaper";
        },
        .linux, .freebsd => blk: {
            const wall_path = try kf.getPath(io, alloc, env, .home);
            const wall_conc = try std.fs.path.join(alloc, &[_][]const u8{ wall_path.?, "newMass/Wallpaper" });
            break :blk wall_conc;
        },
        else => std.debug.assert(false),
    };

    var dir = try IO.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer IO.Dir.close(dir, io);
    var walk = dir.iterate();

    var str_table: Self = .{};
    defer str_table.deinit(alloc);

    while (try walk.next(io)) |elem| {
        if (elem.kind == .file) {
            const id = std.hash.Crc32.hash(elem.name);
            try std.testing.expectEqual(try str_table.insert(alloc, id, try std.fmt.allocPrint(alloc, "{s}", .{elem.name})), true);
        }
    }
}

test "String Table Serialize And Deserialze" {
    const builtin = @import("builtin");
    var testing_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer testing_arena.deinit();
    const alloc = testing_arena.allocator();
    const io = std.testing.io;
    var env = try std.testing.io_instance.environ.process_environ.createMap(alloc);
    defer env.deinit();

    const path = switch (builtin.os.tag) {
        .windows => blk: {
            const doc_path = try kf.getPath(io, alloc, env, .home);
            const doc_conc = try std.fs.path.join(alloc, &[_][]const u8{ doc_path.?, "\\Documents\\wall" });
            var dir_check: bool = true;
            IO.Dir.cwd().access(io, doc_conc, .{}) catch |err| {
                dir_check = if (err == error.FileNotFound) false else true;
            };
            break :blk if (dir_check) doc_conc else "D:/Wallpaper";
        },
        .linux => blk: {
            const wall_path = try kf.getPath(io, alloc, env, .home);
            const wall_conc = try std.fs.path.join(alloc, &[_][]const u8{ wall_path.?, "newMass/Wallpaper" });
            break :blk wall_conc;
        },
        else => std.debug.assert(false),
    };

    var dir = try IO.Dir.cwd().openDir(io, path, .{ .iterate = true });
    defer IO.Dir.close(dir, io);
    var walk = dir.iterate();

    var str_table: Self = .{};
    defer str_table.deinit(alloc);

    while (try walk.next(io)) |elem| {
        if (elem.kind == .file) {
            const id = std.hash.Crc32.hash(elem.name);
            _ = try str_table.insert(alloc, id, try std.fmt.allocPrint(alloc, "{s}", .{elem.name}));
        }
    }

    try str_table.serialize(io, &env);

    var str_table2: Self = .{};
    defer str_table2.deinit(alloc);

    try std.testing.expectEqual(try str_table2.deserialize(alloc, io, &env), true);

    try std.testing.expectEqualDeep(str_table.table_store.items(.id), str_table2.table_store.items(.id));
    try std.testing.expectEqualDeep(str_table.table_store.items(.str), str_table2.table_store.items(.str));
}
