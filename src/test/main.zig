//! geometry2 test runner.
//! linalg의 각 함수에 대한 회귀 테스트.

const std = @import("std");
const geometry2 = @import("geometry2");
const linalg = @import("linalg");
const Vec2f32 = linalg.Vec2(f32);
const Vec3f32 = linalg.Vec3f32;
const Mat4x4f32 = linalg.Mat4x4f32;

// ============================================================================
// Helper: 행렬 비교 유틸
// ============================================================================

/// 두 Mat4x4f32를 원소 단위로 비교한다.
fn expectMatEq(a: Mat4x4f32, b: Mat4x4f32, label: []const u8) !void {
    const eps: f32 = 1e-5;
    for (0..4) |col| {
        for (0..4) |row| {
            const diff = @abs(a.data[col][row] - b.data[col][row]);
            if (diff > eps) {
                std.debug.print("FAIL {s}[{d}][{d}]: expected {d}, got {d}\n", .{
                    label, col, row, b.data[col][row], a.data[col][row],
                });
                return error.TestFailed;
            }
        }
    }
}

/// 행렬이 identity인지 검증한다.
fn expectMatIdentity(m: Mat4x4f32) !void {
    for (0..4) |col| {
        for (0..4) |row| {
            const expected: f32 = if (col == row) 1.0 else 0.0;
            try std.testing.expect(@abs(m.data[col][row] - expected) < 1e-5);
        }
    }
}

/// 점 벡터가 기대값과近似동일한지 검증한다.
fn expectVec4Eq(v: @Vector(4, f32), expected: @Vector(4, f32), eps: f32) !void {
    try std.testing.expect(@abs(v[0] - expected[0]) < eps);
    try std.testing.expect(@abs(v[1] - expected[1]) < eps);
    try std.testing.expect(@abs(v[2] - expected[2]) < eps);
    try std.testing.expect(@abs(v[3] - expected[3]) < eps);
}

pub fn main() !void {
    // ========================================================================
    // 저가치 sanity 테스트 제거: epsilon, matrix2d 컴파일, Circle.rectRadius 등
    // 이식된 동작은 이후 테이블/회귀 테스트에서 커버한다.
    // ========================================================================

    // ========================================================================
    // 1. 기하 기본 연산 (rect, pointInTriangle, rectAnd, linesIntersect2,
    //    pointInPolygon, polygonSignedArea, crossProductSign, inCircleTest,
    //    xyMirrorPoint, BezierKind eval)
    // ========================================================================
    {
        // Rect init
        const r = linalg.rectInit(f32, 1.0, 5.0, 2.0, 4.0);
        try std.testing.expect(r.left == 1.0);
        try std.testing.expect(r.right == 5.0);
        try std.testing.expect(r.top == 2.0);
        try std.testing.expect(r.bottom == 4.0);

        // pointInTriangle: inside + outside
        const tri_a = Vec2f32{ .x = 0, .y = 0 };
        const tri_b = Vec2f32{ .x = 10, .y = 0 };
        const tri_c = Vec2f32{ .x = 0, .y = 10 };
        try std.testing.expect(linalg.pointInTriangle(f32, Vec2f32{ .x = 2, .y = 2 }, tri_a, tri_b, tri_c));
        try std.testing.expect(!linalg.pointInTriangle(f32, Vec2f32{ .x = 20, .y = 20 }, tri_a, tri_b, tri_c));

        // rectAnd: 교집합
        const a = linalg.rectInit(f32, 0, 10, 0, 10);
        const b = linalg.rectInit(f32, 5, 15, 5, 15);
        const inter = linalg.rectAnd(f32, a, b);
        try std.testing.expect(inter.left == 5);
        try std.testing.expect(inter.right == 10);

        // linesIntersect2: 십자 교차
        const res = linalg.linesIntersect2(
            f32,
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 10, .y = 0 },
            Vec2f32{ .x = 5, .y = -5 },
            Vec2f32{ .x = 5, .y = 5 },
            false,
        );
        try std.testing.expect(res[0] == .intersect);
        try std.testing.expect(@abs(res[1].x - 5) < 1e-5);
        try std.testing.expect(@abs(res[1].y - 0) < 1e-5);

        // pointInPolygon: 사각형 내부/외부
        const poly = [_]Vec2f32{
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 10, .y = 0 },
            Vec2f32{ .x = 10, .y = 10 },
            Vec2f32{ .x = 0, .y = 10 },
        };
        try std.testing.expect(linalg.pointInPolygon(f32, Vec2f32{ .x = 5, .y = 5 }, &poly) == .Inside);
        try std.testing.expect(linalg.pointInPolygon(f32, Vec2f32{ .x = 20, .y = 20 }, &poly) == .Outside);

        // polygonSignedArea: 100 (10×10)
        try std.testing.expect(linalg.polygonSignedArea(&poly) == 100.0);

        // crossProductSign: 양수 (반시계)
        try std.testing.expect(linalg.crossProductSign(f32, Vec2f32{ .x = 0, .y = 0 }, Vec2f32{ .x = 10, .y = 0 }, Vec2f32{ .x = 0, .y = 10 }) > 0);

        // inCircleTest: 양수 (내부)
        try std.testing.expect(linalg.inCircleTest(f32, Vec2f32{ .x = 0, .y = 0 }, Vec2f32{ .x = 10, .y = 0 }, Vec2f32{ .x = 0, .y = 10 }, Vec2f32{ .x = 2, .y = 2 }) > 0);

        // xyMirrorPoint: (5,5) → 중심(3,3) → (7,7)
        const mirrored = linalg.xyMirrorPoint(f32, Vec2f32{ .x = 5, .y = 5 }, Vec2f32{ .x = 3, .y = 3 });
        try std.testing.expect(mirrored.x == 7);
        try std.testing.expect(mirrored.y == 7);

        // evalBezierSegment: cubic mid point
        const bezier_pts = [4]Vec2f32{
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 5, .y = 10 },
            Vec2f32{ .x = 15, .y = 10 },
            Vec2f32{ .x = 20, .y = 0 },
        };
        const mid = linalg.evalBezierSegment(f32, .Cubic, bezier_pts, 0.5);
        try std.testing.expect(mid.x > 0);
        try std.testing.expect(mid.y > 0);
    }

    // ========================================================================
    // 2. 행렬 정확성 검증 (table-driven)
    // ========================================================================
    {
        // 2-1) 기본 변환语义: t2dMatrix, s2dMatrix, r2dMatrix
        const t = linalg.t2dMatrix(.{ 1, 2, 0 });
        try expectVec4Eq(linalg.Mat4x4f32.mulVec(t, @Vector(4, f32){ 0, 0, 0, 1 }), @Vector(4, f32){ 1, 2, 0, 1 }, 1e-5);

        const sc = linalg.s2dMatrix(Vec2f32{ .x = 2, .y = 3 });
        try expectVec4Eq(linalg.Mat4x4f32.mulVec(sc, @Vector(4, f32){ 1, 1, 0, 1 }), @Vector(4, f32){ 2, 3, 0, 1 }, 1e-5);

        const pi_half: f32 = std.math.pi / 2.0;
        const r = linalg.r2dMatrix(pi_half);
        try expectVec4Eq(linalg.Mat4x4f32.mulVec(r, @Vector(4, f32){ 1, 0, 0, 1 }), @Vector(4, f32){ 0, 1, 0, 1 }, 1e-5);

        // 2-2) identity * v == v
        const id = linalg.Mat4x4f32.identity();
        try expectVec4Eq(linalg.Mat4x4f32.mulVec(id, @Vector(4, f32){ 7, -3, 5, 1 }), @Vector(4, f32){ 7, -3, 5, 1 }, 1e-5);

        // 2-3) inverse(I) == I
        try expectMatIdentity(id.inverse());

        // 2-4) inverse * M == I (srt2dMatrix)
        const m_test = linalg.srt2dMatrix(.{ 5, -3, 1 }, Vec2f32{ .x = 2, .y = 4 }, 0.7);
        const inv_m = m_test.inverse();
        try expectMatIdentity(m_test.mul(inv_m));

        // 2-5) T*R*S == srt2dMatrix (닫은 형태 일관성)
        const t_mat = linalg.Mat4x4f32.translate(.{ 10, 20, 0 });
        const r_mat = linalg.Mat4x4f32.rotateZ(0.5);
        const s_mat = linalg.Mat4x4f32.scale(.{ 2, 3, 1 });
        const combined = t_mat.mul(r_mat.mul(s_mat));
        const manual = linalg.srt2dMatrix(.{ 10, 20, 0 }, Vec2f32{ .x = 2, .y = 3 }, 0.5);
        try expectMatEq(combined, manual, "srt-vs-manual");

        // 2-6) 역방향 곱: M^-1 * M == I
        try expectMatIdentity(inv_m.mul(m_test));

        // 2-7) 점 단위 역변환 검증
        const v_test = @Vector(4, f32){ 3, 7, 0, 1 };
        const v_back = linalg.Mat4x4f32.mulVec(inv_m, linalg.Mat4x4f32.mulVec(m_test, v_test));
        try expectVec4Eq(v_back, v_test, 1e-5);

        // 2-8) 테이블driven inverse 검증
        const inverse_cases = [_]struct { name: []const u8, m: Mat4x4f32 }{
            .{ .name = "t2dMatrix", .m = linalg.t2dMatrix(.{ 100, 50, 0 }) },
            .{ .name = "s2dMatrix", .m = linalg.s2dMatrix(Vec2f32{ .x = 3, .y = 7 }) },
            .{ .name = "r2dMatrix", .m = linalg.r2dMatrix(1.234) },
            .{ .name = "srt2dMatrix", .m = linalg.srt2dMatrix(.{ 1, 2, 3 }, Vec2f32{ .x = 2, .y = 2 }, 0.5) },
            .{ .name = "srtc2dMatrix", .m = linalg.srtc2dMatrix(.{ 0, 0, 0 }, Vec2f32{ .x = 1, .y = 1 }, 0.0, Vec2f32{ .x = 0.5, .y = 0.5 }) },
        };
        for (inverse_cases) |c| {
            try expectMatIdentity(c.m.inverse().mul(c.m));
        }

        // 2-9) column-major 표기: translate(10,20,0) → data[3] = {10,20,0,1}
        try std.testing.expect(t_mat.data[3][0] == 10);
        try std.testing.expect(t_mat.data[3][1] == 20);
        try std.testing.expect(t_mat.data[3][2] == 0);
        try std.testing.expect(t_mat.data[3][3] == 1);

        // 2-10) rotation π/2: cos=0, sin=1 pattern
        const r_pi_2 = linalg.Mat4x4f32.rotateZ(std.math.pi / 2.0);
        try std.testing.expect(@abs(r_pi_2.data[0][0]) < 1e-6);
        try std.testing.expect(@abs(r_pi_2.data[0][1] - 1) < 1e-6);
        try std.testing.expect(@abs(r_pi_2.data[1][0] - -1) < 1e-6);
        try std.testing.expect(@abs(r_pi_2.data[1][1]) < 1e-6);
    }

    // ========================================================================
    // 3. matrix2d 닫힌 형태 최적화 검증 (table-driven)
    // ========================================================================
    {
        // 참조 구현: 일반 4×4 곱으로 행렬을 만든다 (shortcut 사용 금지).
        const refSrt2dMatrix = struct {
            fn compute(t: Vec3f32, s: Vec2f32, r: f32) Mat4x4f32 {
                const translation = Mat4x4f32.translate(t);
                const rotation = Mat4x4f32.rotateZ(r);
                const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
                return translation.mul(rotation.mul(scale));
            }
        }.compute;

        const refSrtc2dMatrix = struct {
            fn compute(t: Vec3f32, s: Vec2f32, r: f32, cp: Vec2f32) Mat4x4f32 {
                const translation = Mat4x4f32.translate(t);
                const rotation = Mat4x4f32.rotateZ(r);
                const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
                const pivot = Mat4x4f32.translate(Vec3f32{ cp.x, cp.y, 0.0 });
                return translation.mul(rotation.mul(scale.mul(pivot)));
            }
        }.compute;

        const refSt2dMatrix = struct {
            fn compute(t: Vec3f32, s: Vec2f32) Mat4x4f32 {
                const translation = Mat4x4f32.translate(t);
                const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
                return translation.mul(scale);
            }
        }.compute;

        const refRt2dMatrix = struct {
            fn compute(t: Vec3f32, r: f32) Mat4x4f32 {
                const translation = Mat4x4f32.translate(t);
                const rotation = Mat4x4f32.rotateZ(r);
                return translation.mul(rotation);
            }
        }.compute;

        const refSr2dMatrix = struct {
            fn compute(s: Vec2f32, r: f32) Mat4x4f32 {
                const rotation = Mat4x4f32.rotateZ(r);
                const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
                return rotation.mul(scale);
            }
        }.compute;

        const refSrc2dMatrix = struct {
            fn compute(s: Vec2f32, r: f32, cp: Vec2f32) Mat4x4f32 {
                const rotation = Mat4x4f32.rotateZ(r);
                const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
                const pivot = Mat4x4f32.translate(Vec3f32{ cp.x, cp.y, 0.0 });
                return rotation.mul(scale.mul(pivot));
            }
        }.compute;

        // srt2dMatrix 테이블
        {
            const m = linalg.srt2dMatrix(.{ 10, 20, 0 }, .{ .x = 2, .y = 3 }, 0.5);
            try expectMatEq(m, refSrt2dMatrix(.{ 10, 20, 0 }, .{ .x = 2, .y = 3 }, 0.5), "srt2dMatrix");
        }
        {
            const m = linalg.srt2dMatrix(.{ -5, 7, 1 }, .{ .x = 4, .y = 1 }, 0.0);
            try expectMatEq(m, refSrt2dMatrix(.{ -5, 7, 1 }, .{ .x = 4, .y = 1 }, 0.0), "srt2dMatrix-zero-rot");
        }
        {
            const m = linalg.srt2dMatrix(.{ 0, 0, 0 }, .{ .x = 1, .y = 1 }, 1.234);
            try expectMatEq(m, refSrt2dMatrix(.{ 0, 0, 0 }, .{ .x = 1, .y = 1 }, 1.234), "srt2dMatrix-unit-scale");
        }
        {
            const m = linalg.srt2dMatrix(.{ 3, -2, 0 }, .{ .x = -1, .y = -2 }, 0.789);
            try expectMatEq(m, refSrt2dMatrix(.{ 3, -2, 0 }, .{ .x = -1, .y = -2 }, 0.789), "srt2dMatrix-neg-scale");
        }

        // srtc2dMatrix 테이블
        {
            const m = linalg.srtc2dMatrix(.{ 10, 20, 0 }, .{ .x = 2, .y = 3 }, 0.5, .{ .x = 4, .y = 5 });
            try expectMatEq(m, refSrtc2dMatrix(.{ 10, 20, 0 }, .{ .x = 2, .y = 3 }, 0.5, .{ .x = 4, .y = 5 }), "srtc2dMatrix");
        }
        {
            const m = linalg.srtc2dMatrix(.{ 1, 2, 3 }, .{ .x = 1, .y = 1 }, 0.0, .{ .x = -2, .y = -3 });
            try expectMatEq(m, refSrtc2dMatrix(.{ 1, 2, 3 }, .{ .x = 1, .y = 1 }, 0.0, .{ .x = -2, .y = -3 }), "srtc2dMatrix-neg-pivot");
        }
        // cp=(0,0) → srt2dMatrix와 같음
        {
            const m = linalg.srtc2dMatrix(.{ 5, 6, 0 }, .{ .x = 3, .y = 4 }, 0.25, .{ .x = 0, .y = 0 });
            try expectMatEq(m, refSrtc2dMatrix(.{ 5, 6, 0 }, .{ .x = 3, .y = 4 }, 0.25, .{ .x = 0, .y = 0 }), "srtc2dMatrix-cp0");
        }

        // src2dMatrix 테이블
        const src_cp0 = linalg.src2dMatrix(.{ .x = 2, .y = 3 }, 0.5, .{ .x = 0, .y = 0 });
        try expectMatEq(src_cp0, linalg.sr2dMatrix(.{ .x = 2, .y = 3 }, 0.5), "src2dMatrix-cp0=sr2dMatrix");
        try expectMatEq(src_cp0, refSrc2dMatrix(.{ .x = 2, .y = 3 }, 0.5, .{ .x = 0, .y = 0 }), "src2dMatrix-cp0=ref");

        {
            const m = linalg.src2dMatrix(.{ .x = 2, .y = 3 }, 0.5, .{ .x = 4, .y = 5 });
            try expectMatEq(m, refSrc2dMatrix(.{ .x = 2, .y = 3 }, 0.5, .{ .x = 4, .y = 5 }), "src2dMatrix-cp");
        }
        {
            const m = linalg.src2dMatrix(.{ .x = 1, .y = 1 }, 0.0, .{ .x = 7, .y = 8 });
            try expectMatEq(m, refSrc2dMatrix(.{ .x = 1, .y = 1 }, 0.0, .{ .x = 7, .y = 8 }), "src2dMatrix-cp-unit-scale");
        }

        // st2dMatrix 테이블
        {
            const m = linalg.st2dMatrix(.{ 10, 20, 0 }, .{ .x = 2, .y = 3 });
            try expectMatEq(m, refSt2dMatrix(.{ 10, 20, 0 }, .{ .x = 2, .y = 3 }), "st2dMatrix");
        }
        {
            const m = linalg.st2dMatrix(.{ -1, -2, 5 }, .{ .x = 1, .y = 1 });
            try expectMatEq(m, refSt2dMatrix(.{ -1, -2, 5 }, .{ .x = 1, .y = 1 }), "st2dMatrix-unit-scale");
        }

        // rt2dMatrix 테이블
        {
            const m = linalg.rt2dMatrix(.{ 10, 20, 0 }, 0.5);
            try expectMatEq(m, refRt2dMatrix(.{ 10, 20, 0 }, 0.5), "rt2dMatrix");
        }
        {
            const m = linalg.rt2dMatrix(.{ 0, 0, 0 }, 0.0);
            try expectMatEq(m, refRt2dMatrix(.{ 0, 0, 0 }, 0.0), "rt2dMatrix-zero-rot");
        }

        // sr2dMatrix 테이블
        {
            const m = linalg.sr2dMatrix(.{ .x = 2, .y = 3 }, 0.5);
            try expectMatEq(m, refSr2dMatrix(.{ .x = 2, .y = 3 }, 0.5), "sr2dMatrix");
        }
        {
            const m = linalg.sr2dMatrix(.{ .x = 1, .y = 1 }, 0.0);
            try expectMatEq(m, refSr2dMatrix(.{ .x = 1, .y = 1 }, 0.0), "sr2dMatrix-unit-scale");
        }

        // srt2dMatrix2 short-circuit: 모두 identity → t2dMatrix
        {
            const m = linalg.srt2dMatrix2(.{ 7, 8, 9 }, .{ .x = 1, .y = 1 }, 0.0, .{ .x = 0, .y = 0 });
            try expectMatEq(m, linalg.t2dMatrix(.{ 7, 8, 9 }), "srt2dMatrix2-identity");
        }

        // sr2dMatrix2 short-circuit: 모두 identity → null
        {
            const m = linalg.sr2dMatrix2(.{ .x = 1, .y = 1 }, 0.0, .{ .x = 0, .y = 0 });
            try std.testing.expect(m == null);
        }

        // sr2dMatrix2: rotation만 있으면 r2dMatrix
        {
            const m = linalg.sr2dMatrix2(.{ .x = 1, .y = 1 }, 0.5, .{ .x = 0, .y = 0 });
            try std.testing.expect(m != null);
            if (m) |val| {
                try expectMatEq(val, linalg.r2dMatrix(0.5), "sr2dMatrix2-rotation-only");
            }
        }

        // srt2dMatrix2: scale만 있으면 st2dMatrix
        {
            const m = linalg.srt2dMatrix2(.{ 3, 4, 0 }, .{ .x = 5, .y = 6 }, 0.0, .{ .x = 0, .y = 0 });
            try expectMatEq(m, linalg.st2dMatrix(.{ 3, 4, 0 }, .{ .x = 5, .y = 6 }), "srt2dMatrix2-scale-only");
        }
    }

    // ========================================================================
    // 4. path_template (CircleCubicInit / RectLineInit /
    //                   RoundRectLineInit / EllipseCubicInit)
    // ========================================================================
    {
        const r0 = linalg.rectInit(f32, 0.0, 10.0, 0.0, 10.0);

        // RectLineInit
        const rp = linalg.rectLineInit(f32, r0);
        try std.testing.expect(rp.len == 4);
        try std.testing.expect(rp[0].x == 0.0 and rp[0].y == 0.0);
        try std.testing.expect(rp[2].x == 10.0 and rp[2].y == 10.0);

        // CircleCubicInit
        const cc = linalg.circleCubicInit(f32, Vec2f32{ .x = 0, .y = 0 }, 5.0);
        try std.testing.expect(cc.pts.len == 12);
        try std.testing.expect(cc.isCurves.len == 12);
        try std.testing.expect(cc.pts[0].x == -5.0 and cc.pts[0].y == 0.0);
        try std.testing.expect(cc.pts[6].x == 5.0 and cc.pts[6].y == 0.0);
        try std.testing.expect(cc.isCurves[0] == false);
        try std.testing.expect(cc.isCurves[1] == true);

        // EllipseCubicInit
        const ee = linalg.ellipseCubicInit(f32, Vec2f32{ .x = 0, .y = 0 }, Vec2f32{ .x = 3, .y = 2 });
        try std.testing.expect(ee.pts.len == 12);
        try std.testing.expect(ee.isCurves.len == 12);
        try std.testing.expect(ee.pts[0].x == -3.0 and ee.pts[0].y == 0.0);
        try std.testing.expect(ee.pts[3].x == 0.0 and ee.pts[3].y == -2.0);

        // RoundRectLineInit
        const rr = linalg.roundRectLineInit(f32, r0, 1.0);
        try std.testing.expect(rr.pts.len == 12);
        try std.testing.expect(rr.isCurves.len == 12);
        try std.testing.expect(rr.pts[0].x == 1.0 and rr.pts[0].y == 0.0);
        try std.testing.expect(rr.isCurves[1] == true);
    }

    // ========================================================================
    // 5. polyTransformMatrix (행렬 변환 의미 검증)
    // ========================================================================
    {
        var pts_arr = [_]Vec2f32{
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 10, .y = 0 },
            Vec2f32{ .x = 10, .y = 10 },
        };
        var curves_arr = [_]bool{ false, false, false };
        var pts_slice = [_][]Vec2f32{&pts_arr};
        var isCurves_slice = [_][]bool{&curves_arr};
        var node = linalg.ShapeNode{
            .pts = &pts_slice,
            .isCurves = &isCurves_slice,
            .color = @Vector(4, f32){ 0, 0, 0, 1.0 },
            .strokeColor = @Vector(4, f32){ 0, 0, 0, 0 },
            .thickness = 0,
            .isClosed = true,
            .clipRect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 },
        };
        var shapes = linalg.Shapes{ .nodes = (&node)[0..1], .clipRect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 } };

        // identity: 점 불변
        linalg.polyTransformMatrix(&shapes, linalg.Mat4x4f32.identity());
        try std.testing.expect(shapes.nodes[0].pts[0][0].x == 0.0);
        try std.testing.expect(shapes.nodes[0].pts[0][0].y == 0.0);
        try std.testing.expect(shapes.nodes[0].pts[0][1].x == 10.0);
        try std.testing.expect(shapes.nodes[0].pts[0][1].y == 0.0);
        try std.testing.expect(shapes.nodes[0].pts[0][2].x == 10.0);
        try std.testing.expect(shapes.nodes[0].pts[0][2].y == 10.0);

        // translation (5, 7, 0): (0,0)→(5,7), (10,0)→(15,7)
        linalg.polyTransformMatrix(&shapes, linalg.Mat4x4f32.translate(.{ 5, 7, 0 }));
        try std.testing.expect(shapes.nodes[0].pts[0][0].x == 5.0);
        try std.testing.expect(shapes.nodes[0].pts[0][0].y == 7.0);
        try std.testing.expect(shapes.nodes[0].pts[0][1].x == 15.0);
        try std.testing.expect(shapes.nodes[0].pts[0][1].y == 7.0);
    }

    // ========================================================================
    // 6. shapesComputePolygon (line-only polygon → RawShape)
    // ========================================================================
    {
        var pts_arr = [_]Vec2f32{
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 10, .y = 0 },
            Vec2f32{ .x = 10, .y = 10 },
        };
        var curves_arr = [_]bool{ false, false, false };
        var pts_slice = [_][]Vec2f32{&pts_arr};
        var isCurves_slice = [_][]bool{&curves_arr};
        var node = linalg.ShapeNode{
            .pts = &pts_slice,
            .isCurves = &isCurves_slice,
            .color = @Vector(4, f32){ 0, 0, 0, 1.0 },
            .strokeColor = @Vector(4, f32){ 0, 0, 0, 0 },
            .thickness = 0,
            .isClosed = true,
            .clipRect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 },
        };
        const shapes = linalg.Shapes{ .nodes = (&node)[0..1], .clipRect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 } };

        var gpa = std.heap.DebugAllocator(.{}).init;
        defer _ = gpa.deinit();
        const test_alloc = gpa.allocator();

        var arena = std.heap.ArenaAllocator.init(test_alloc);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const raw = try linalg.shapesComputePolygon(shapes, arena_alloc);
        const user_raw = linalg.RawShape{
            .vertices = try test_alloc.dupe(linalg.ShapeVertex2d, raw.vertices),
            .indices = try test_alloc.dupe(u32, raw.indices),
            .rect = raw.rect,
        };
        defer linalg.rawShapeFree(@constCast(&user_raw), test_alloc);

        try std.testing.expect(user_raw.vertices.len > 0);
        try std.testing.expect(user_raw.indices.len > 0);
        try std.testing.expect(user_raw.rect.left <= user_raw.rect.right);
    }

    // ========================================================================
    // 7. SVG 파싱: Q→CUBIC 변환, isCurves 보존, Y-flip 검증
    // ========================================================================
    {
        const svg_text =
            \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            \\  <path d="M 10 10 Q 50 90 90 10 Q 50 50 10 10 Z" fill="black" />
            \\</svg>
        ;

        var gpa = std.heap.DebugAllocator(.{}).init;
        defer _ = gpa.deinit();
        const test_alloc = gpa.allocator();

        var parser = try linalg.svg.initParse(svg_text, test_alloc);
        defer parser.deinit();

        try std.testing.expect(parser.shapes.nodes.len == 1);
        const node = parser.shapes.nodes[0];
        try std.testing.expect(node.pts.len == 1);
        const contour = node.pts[0];
        try std.testing.expect(contour.len == 6);
        try std.testing.expect(node.isCurves.len == 1);
        const curves = node.isCurves[0];
        try std.testing.expect(curves.len == 6);

        // M 10 10 → Y-flip → (10, -10)
        try std.testing.expect(@abs(contour[0].x - 10.0) < 1e-5);
        try std.testing.expect(@abs(contour[0].y - -10.0) < 1e-5);
        // CLOSE 후 중복점 제거된 마지막 점
        try std.testing.expect(@abs(contour[5].x - 36.67) < 0.01);
        try std.testing.expect(@abs(contour[5].y - -36.67) < 0.01);

        // isCurves 패턴: [false, true, true, false, true, true]
        try std.testing.expect(curves[0] == false);
        try std.testing.expect(curves[1] == true);
        try std.testing.expect(curves[2] == true);
        try std.testing.expect(curves[3] == false);
        try std.testing.expect(curves[4] == true);
        try std.testing.expect(curves[5] == true);
    }

    // ========================================================================
    // 8. Rasterizer end-to-end: SVG → shapes → pixels (non-zero 확인)
    // ========================================================================
    {
        const svg_text =
            \\<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
            \\  <path d="M 10 10 L 90 10 L 90 90 L 10 90 Z" fill="black" />
            \\</svg>
        ;

        var gpa = std.heap.DebugAllocator(.{}).init;
        defer _ = gpa.deinit();
        const test_alloc = gpa.allocator();

        var parser = try linalg.svg.initParse(svg_text, test_alloc);
        defer parser.deinit();

        try std.testing.expect(parser.shapes.nodes.len == 1);
        try std.testing.expect(parser.shapes.nodes[0].pts.len == 1);
        try std.testing.expect(parser.shapes.nodes[0].pts[0].len == 4);

        const pixels = try linalg.rasterizer.shapesToPixels(parser.shapes, 100, 100, test_alloc);
        defer linalg.rasterizer.rasterizedPixelsFree(@constCast(&pixels));

        try std.testing.expect(pixels.width == 100);
        try std.testing.expect(pixels.height == 100);
        try std.testing.expect(pixels.pixels.len > 0);

        var has_nonzero = false;
        for (pixels.pixels) |byte| {
            if (byte != 0) {
                has_nonzero = true;
                break;
            }
        }
        try std.testing.expect(has_nonzero);
    }

    // ========================================================================
    // 9. Geometry aggregator: shapesComputePolygon, getCubicCurveType,
    //    reverseShapeCloseCurve (오류/정상 케이스)
    // ========================================================================
    {
        var gpa = std.heap.DebugAllocator(.{}).init;
        defer _ = gpa.deinit();
        const test_alloc = gpa.allocator();

        // shapesComputePolygon: CCW 삼각형 (line-only)
        {
            var arena = std.heap.ArenaAllocator.init(test_alloc);
            defer arena.deinit();
            const arena_alloc = arena.allocator();

            var tpts = [_]Vec2f32{
                Vec2f32{ .x = 0, .y = -100 },
                Vec2f32{ .x = 100, .y = -100 },
                Vec2f32{ .x = 100, .y = 0 },
            };
            var tcurves = [_]bool{ false, false, false };
            var tpts_slice = [_][]Vec2f32{&tpts};
            var tcurves_slice = [_][]bool{&tcurves};
            var tnode = linalg.ShapeNode{
                .pts = &tpts_slice,
                .isCurves = &tcurves_slice,
                .color = @Vector(4, f32){ 0, 0, 0, 1.0 },
                .strokeColor = @Vector(4, f32){ 0, 0, 0, 0 },
                .thickness = 0,
                .isClosed = true,
                .clipRect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 },
            };
            const tshapes = linalg.Shapes{ .nodes = (&tnode)[0..1], .clipRect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 } };

            const raw = try linalg.shapesComputePolygon(tshapes, arena_alloc);
            try std.testing.expect(raw.vertices.len > 0);
            try std.testing.expect(raw.indices.len > 0);
        }

        // getCubicCurveType: 동일선상 → Line 또는 Quadratic
        {
            const result = try linalg.getCubicCurveType(
                f32,
                Vec2f32{ .x = 0, .y = 0 },
                Vec2f32{ .x = 1, .y = 1 },
                Vec2f32{ .x = 2, .y = 2 },
                Vec2f32{ .x = 3, .y = 3 },
            );
            std.debug.print("getCubicCurveType: type={s} d0={d} d1={d} d2={d}\n", .{
                @tagName(result.curveType), result.d0, result.d1, result.d2,
            });
            try std.testing.expect(result.curveType == .Line or result.curveType == .Quadratic);
        }

        // getCubicCurveType: 점 오류 → IsPointNotLine
        {
            const p = Vec2f32{ .x = 0, .y = 0 };
            const err = linalg.getCubicCurveType(f32, p, p, p, p);
            try std.testing.expectError(error.IsPointNotLine, err);
        }

        // reverseShapeCloseCurve: all-anchor → 오류 (예상)
        {
            const pts = [_]Vec2f32{
                Vec2f32{ .x = 0, .y = 0 },
                Vec2f32{ .x = 10, .y = 0 },
                Vec2f32{ .x = 10, .y = 10 },
                Vec2f32{ .x = 0, .y = 10 },
            };
            const curves = [_]bool{ false, false, false, false };
            const err = linalg.reverseShapeCloseCurve(&pts, &curves, test_alloc);
            try std.testing.expectError(error.Consecutive_Anchor_Missing_Control, err);
        }

        // reverseShapeCloseCurve: anchor-curve-anchor → 정상
        {
            const pts = [_]Vec2f32{
                Vec2f32{ .x = 0, .y = 0 },
                Vec2f32{ .x = 2, .y = 5 },
                Vec2f32{ .x = 5, .y = 5 },
                Vec2f32{ .x = 5, .y = 7 },
                Vec2f32{ .x = 10, .y = 8 },
            };
            const curves = [_]bool{ false, true, false, true, true };
            const result = try linalg.reverseShapeCloseCurve(&pts, &curves, test_alloc);
            defer test_alloc.free(result.pts);
            defer test_alloc.free(result.isCurves);

            try std.testing.expect(result.pts.len == pts.len);
            try std.testing.expect(result.isCurves.len == curves.len);
            try std.testing.expect(!result.isCurves[0]);
        }
    }

    std.debug.print("linalg sanity: OK\n", .{});
}
