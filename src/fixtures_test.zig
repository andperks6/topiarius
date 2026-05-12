//! Fixture-corpus test. Walks `test/fixtures/`, finds every `*.in` file,
//! and asserts that the transform output equals the sibling `*.out` file.
//!
//! Naming convention: `<name>.<level>.in` and `<name>.<level>.out`, where
//! `<level>` is one of `low`, `normal`, `high`. If the level token is absent
//! (`<name>.in`), the case is exercised at `normal` aggressiveness.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const transform_mod = @import("transform");
const test_config = @import("test_config");

const max_fixture_bytes = 1 * 1024 * 1024;

fn parseLevelFromName(stem: []const u8) struct { name: []const u8, level: transform_mod.Level } {
    // Strip a trailing `.<level>` if present.
    const levels = [_]struct { token: []const u8, level: transform_mod.Level }{
        .{ .token = ".low", .level = .low },
        .{ .token = ".normal", .level = .normal },
        .{ .token = ".high", .level = .high },
    };
    inline for (levels) |entry| {
        if (std.mem.endsWith(u8, stem, entry.token)) {
            return .{
                .name = stem[0 .. stem.len - entry.token.len],
                .level = entry.level,
            };
        }
    }
    return .{ .name = stem, .level = .normal };
}

fn readAll(io: Io, dir: Io.Dir, allocator: Allocator, sub_path: []const u8) ![]u8 {
    var f = try dir.openFile(io, sub_path, .{});
    defer f.close(io);
    var buf: [4096]u8 = undefined;
    var reader = f.reader(io, &buf);
    return reader.interface.allocRemaining(allocator, .limited(max_fixture_bytes));
}

test "fixture corpus" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var dir = try Io.Dir.openDirAbsolute(io, test_config.fixtures_dir, .{ .iterate = true });
    defer dir.close(io);

    var run_count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".in")) continue;

        const stem = entry.name[0 .. entry.name.len - ".in".len];
        const parsed = parseLevelFromName(stem);

        const in_path = try std.fmt.allocPrint(gpa, "{s}", .{entry.name});
        defer gpa.free(in_path);

        const out_path = try std.fmt.allocPrint(gpa, "{s}.out", .{stem});
        defer gpa.free(out_path);

        const input = try readAll(io, dir, gpa, in_path);
        defer gpa.free(input);

        const expected = try readAll(io, dir, gpa, out_path);
        defer gpa.free(expected);

        const actual = try transform_mod.transform(gpa, input, parsed.level);
        defer gpa.free(actual);

        std.testing.expectEqualStrings(expected, actual) catch |err| {
            std.debug.print("\n[fixture failed: {s} @ {s}]\n", .{ entry.name, @tagName(parsed.level) });
            return err;
        };
        run_count += 1;
    }

    if (run_count == 0) return error.NoFixturesFound;
    try std.testing.expect(run_count >= 9);
}
