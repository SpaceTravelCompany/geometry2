const std = @import("std");
const builtin = @import("builtin");

pub fn defaultTargetQuery() std.Target.Query {
    return if (builtin.target.os.tag == .windows) .{
        .abi = .msvc,
    } else .{};
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = defaultTargetQuery() });
    const optimize = b.standardOptimizeOption(.{});

    // ── linalg 모듈 ──────────────────────────────────────────────────────
    const linalg_mod = b.addModule("linalg", .{
        .root_source_file = b.path("src/linalg/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    // libtess2 C 소스를 linalg 모듈에 직접 통합
    linalg_mod.addCSourceFiles(.{
        .files = &.{
            "deps/libtess2/Source/bucketalloc.c",
            "deps/libtess2/Source/dict.c",
            "deps/libtess2/Source/geom.c",
            "deps/libtess2/Source/mesh.c",
            "deps/libtess2/Source/priorityq.c",
            "deps/libtess2/Source/sweep.c",
            "deps/libtess2/Source/tess.c",
        },
        .flags = &.{"-std=c99"},
    });
    linalg_mod.addIncludePath(b.path("deps/libtess2/Include"));
    linalg_mod.addIncludePath(b.path("deps/libtess2/Source"));
    linalg_mod.link_libc = true;

    // ── zig-xml (ianprime0509/zig-xml, package dependency) ─────────────
    const xml_dep = b.dependency("xml", .{
        .target = target,
        .optimize = optimize,
    });
    const xml_mod = xml_dep.module("xml");

    // linalg/svg.zig 가 zig-xml 을 직접 import 하므로 linalg 모듈에 xml 모듈 제공
    linalg_mod.addImport("xml", xml_mod);

    // ── plutovg C 소스 목록 ─────────────────────────────────────────────
    const plutovg_files = [_][]const u8{
        "deps/plutovg/source/plutovg-blend.c",
        "deps/plutovg/source/plutovg-canvas.c",
        "deps/plutovg/source/plutovg-font.c",
        "deps/plutovg/source/plutovg-ft-math.c",
        "deps/plutovg/source/plutovg-ft-raster.c",
        "deps/plutovg/source/plutovg-ft-stroker.c",
        "deps/plutovg/source/plutovg-matrix.c",
        "deps/plutovg/source/plutovg-paint.c",
        "deps/plutovg/source/plutovg-path.c",
        "deps/plutovg/source/plutovg-rasterize.c",
        "deps/plutovg/source/plutovg-surface.c",
    };

    // ── svg 모듈 ─────────────────────────────────────────────────────────
    const svg_mod = b.addModule("svg", .{
        .root_source_file = b.path("src/linalg/svg.zig"),
        .target = target,
        .optimize = optimize,
    });
    svg_mod.addImport("linalg", linalg_mod);
    svg_mod.addImport("xml", xml_mod);
    svg_mod.addCSourceFiles(.{
        .files = &plutovg_files,
        .flags = &.{ "-std=c99", "-DPLUTOVG_BUILD" },
    });
    svg_mod.addIncludePath(b.path("deps/plutovg/include"));
    svg_mod.link_libc = true;

    // ── rasterizer 모듈 ──────────────────────────────────────────────────
    const rasterizer_mod = b.addModule("rasterizer", .{
        .root_source_file = b.path("src/linalg/rasterizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    rasterizer_mod.addImport("linalg", linalg_mod);
    rasterizer_mod.addCSourceFiles(.{
        .files = &plutovg_files,
        .flags = &.{ "-std=c99", "-DPLUTOVG_BUILD" },
    });
    rasterizer_mod.addIncludePath(b.path("deps/plutovg/include"));
    rasterizer_mod.link_libc = true;

    // ── geometry2 최상위 모듈 ────────────────────────────────────────────
    const geometry2_mod = b.addModule("geometry2", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    geometry2_mod.addImport("linalg", linalg_mod);

    // ── 테스트 실행 파일 ────────────────────────────────────────────────
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("geometry2", geometry2_mod);
    test_mod.addImport("linalg", linalg_mod);
    // linalg/svg 모듈은 svg.zig 를 통해 zig-xml 을 import 하므로 테스트도 xml 모듈을 제공해야 한다.
    test_mod.addImport("xml", xml_mod);
    // rasterizer 와 svg 는 plutovg c-abi 를 직접 호출하므로 테스트 실행 파일도 plutovg 를 링크해야 한다.
    test_mod.addCSourceFiles(.{
        .files = &plutovg_files,
        .flags = &.{ "-std=c99", "-DPLUTOVG_BUILD" },
    });
    test_mod.addIncludePath(b.path("deps/plutovg/include"));
    test_mod.link_libc = true;

    const test_exe = b.addExecutable(.{
        .name = "geometry2_test",
        .root_module = test_mod,
    });
    b.installArtifact(test_exe);

    const run_test = b.addRunArtifact(test_exe);

    // ── 단위 테스트 ────────────────────────────────────────────────────
    const linalg_tests = b.addTest(.{
        .root_module = linalg_mod,
    });
    const run_linalg_tests = b.addRunArtifact(linalg_tests);
    const test_step = b.step("test", "전체 테스트 (단위 테스트 + 실행 파일)");
    test_step.dependOn(&run_linalg_tests.step);
    test_step.dependOn(&run_test.step);

    // ── check step ─────────────────────────────────────────────────────
    const check_step = b.step("check", "전체 테스트 (test alias)");
    check_step.dependOn(&run_linalg_tests.step);
    check_step.dependOn(&run_test.step);
}
