const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const regex_dep = b.dependency("zig_regex", .{
        .target = target,
        .optimize = optimize,
    });

    const transform_mod = b.addModule("transform", .{
        .root_source_file = b.path("src/transform.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "regex", .module = regex_dep.module("regex") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "topia",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "transform", .module = transform_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the topia binary");
    run_step.dependOn(&run_cmd.step);

    // --- Tests ---------------------------------------------------------------

    const fixtures_dir = b.pathFromRoot("test/fixtures");

    const test_opts = b.addOptions();
    test_opts.addOption([]const u8, "fixtures_dir", fixtures_dir);

    // Unit tests on the transform module.
    const transform_tests = b.addTest(.{ .root_module = transform_mod });
    const run_transform_tests = b.addRunArtifact(transform_tests);

    // Fixture-corpus tests live in their own module so they can pull in the
    // build-time `fixtures_dir` option.
    const fixtures_mod = b.createModule(.{
        .root_source_file = b.path("src/fixtures_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "transform", .module = transform_mod },
        },
    });
    fixtures_mod.addOptions("test_config", test_opts);

    const fixtures_tests = b.addTest(.{ .root_module = fixtures_mod });
    const run_fixtures_tests = b.addRunArtifact(fixtures_tests);

    const clipboard_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/clipboard.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const run_clipboard_tests = b.addRunArtifact(clipboard_tests);

    const daemon_test_mod = b.createModule(.{
        .root_source_file = b.path("src/daemon.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "transform", .module = transform_mod },
        },
    });
    const daemon_tests = b.addTest(.{ .root_module = daemon_test_mod });
    const run_daemon_tests = b.addRunArtifact(daemon_tests);

    const signal_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/signal.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const run_signal_tests = b.addRunArtifact(signal_tests);

    const test_step = b.step("test", "Run unit and fixture tests");
    test_step.dependOn(&run_transform_tests.step);
    test_step.dependOn(&run_fixtures_tests.step);
    test_step.dependOn(&run_clipboard_tests.step);
    test_step.dependOn(&run_daemon_tests.step);
    test_step.dependOn(&run_signal_tests.step);

    // --- Release: cross-compile one binary per target into zig-out/release/ ---

    const release_step = b.step("release", "Cross-compile release binaries into zig-out/release/");
    const release_targets = [_]std.Target.Query{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
    };

    for (release_targets) |query| {
        const release_target = b.resolveTargetQuery(query);
        const release_regex = b.dependency("zig_regex", .{
            .target = release_target,
            .optimize = .ReleaseSafe,
        });
        const release_transform_mod = b.createModule(.{
            .root_source_file = b.path("src/transform.zig"),
            .target = release_target,
            .optimize = .ReleaseSafe,
            .imports = &.{
                .{ .name = "regex", .module = release_regex.module("regex") },
            },
        });
        const release_exe = b.addExecutable(.{
            .name = "topia",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = release_target,
                .optimize = .ReleaseSafe,
                .imports = &.{
                    .{ .name = "transform", .module = release_transform_mod },
                },
            }),
        });
        const triple = query.zigTriple(b.allocator) catch @panic("OOM");
        const release_install = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{ .override = .{ .custom = "release" } },
            .dest_sub_path = b.fmt("topia-{s}", .{triple}),
        });
        release_step.dependOn(&release_install.step);
    }
}
