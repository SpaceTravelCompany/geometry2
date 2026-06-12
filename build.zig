const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── 모듈 정의 ──────────────────────────────────────────────────────
    const linalg_mod = b.addModule("linalg", .{
        .root_source_file = b.path("src/linalg/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    // geometry2 최상위 모듈 — root.zig가 linalg를 re-export
    const geometry2_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    geometry2_mod.addImport("linalg", linalg_mod);

    // ── 테스트 실행 파일 (install / run-test) ──────────────────────────
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("geometry2", geometry2_mod);
    test_mod.addImport("linalg", linalg_mod);

    const test_exe = b.addExecutable(.{
        .name = "geometry2_test",
        .root_module = test_mod,
    });
    b.installArtifact(test_exe);

    const run_test = b.addRunArtifact(test_exe);
    const run_test_step = b.step("run-test", "테스트 실행 파일 빌드 + 실행");
    run_test_step.dependOn(&run_test.step);

    // ── 단위 테스트 ────────────────────────────────────────────────────
    const linalg_tests = b.addTest(.{
        .root_module = geometry2_mod,
    });
    const run_linalg_tests = b.addRunArtifact(linalg_tests);
    const test_step = b.step("test", "linalg 단위 테스트");
    test_step.dependOn(&run_linalg_tests.step);

    // ── check step ─────────────────────────────────────────────────────
    const check_step = b.step("check", "전체 모듈 컴파일 체크");
    check_step.dependOn(&run_linalg_tests.step);
}
