//! geometry2 test runner.
//! linalg의 각 함수에 대한 sanity 테스트.

const std = @import("std");
const geometry2 = @import("geometry2");
const linalg = @import("linalg");
const Vec2f32 = linalg.Vec2(f32);

pub fn main() !void {
    var debug_alloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debug_alloc.deinit();
    const alloc = debug_alloc.allocator();
    _ = alloc;

    // sanity: Rect
    {
        const r = linalg.rectInit(f32, 1.0, 5.0, 2.0, 4.0);
        try std.testing.expect(r.left == 1.0);
        try std.testing.expect(r.right == 5.0);
        try std.testing.expect(r.top == 2.0);
        try std.testing.expect(r.bottom == 4.0);
    }

    // sanity: pointInTriangle
    {
        const tri_a = Vec2f32{ .x = 0, .y = 0 };
        const tri_b = Vec2f32{ .x = 10, .y = 0 };
        const tri_c = Vec2f32{ .x = 0, .y = 10 };
        const inside = linalg.pointInTriangle(f32, Vec2f32{ .x = 2, .y = 2 }, tri_a, tri_b, tri_c);
        try std.testing.expect(inside);
        const outside = linalg.pointInTriangle(f32, Vec2f32{ .x = 20, .y = 20 }, tri_a, tri_b, tri_c);
        try std.testing.expect(!outside);
    }

    // sanity: rectAnd / rectOr
    {
        const a = linalg.rectInit(f32, 0, 10, 0, 10);
        const b = linalg.rectInit(f32, 5, 15, 5, 15);
        const inter = linalg.rectAnd(f32, a, b);
        try std.testing.expect(inter.left == 5);
        try std.testing.expect(inter.right == 10);
    }

    // sanity: epsilon
    {
        try std.testing.expect(linalg.epsilon(f32) > 0);
        try std.testing.expect(linalg.epsilon(f64) > 0);
    }

    // sanity: matrix2d
    {
        const m = linalg.t2dMatrix(.{ 1, 2, 3 });
        _ = m;
    }

    // 행렬 정확성 검증
    {
        // 1) t2dMatrix(1, 2, 0) 적용한 후 점 (0,0) → (1, 2)
        const t = linalg.t2dMatrix(.{ 1, 2, 0 });
        const v0 = linalg.Mat4x4f32.mulVec(t, @Vector(4, f32){ 0, 0, 0, 1 });
        try std.testing.expect(@abs(v0[0] - 1) < 1e-5);
        try std.testing.expect(@abs(v0[1] - 2) < 1e-5);

        // 2) identity * v == v
        const id = linalg.Mat4x4f32.identity();
        const v1 = linalg.Mat4x4f32.mulVec(id, @Vector(4, f32){ 7, -3, 5, 1 });
        try std.testing.expect(@abs(v1[0] - 7) < 1e-5);
        try std.testing.expect(@abs(v1[1] - -3) < 1e-5);
        try std.testing.expect(@abs(v1[2] - 5) < 1e-5);
        try std.testing.expect(@abs(v1[3] - 1) < 1e-5);

        // 3) s2dMatrix(2, 3) 점 (1, 1) → (2, 3)
        const sc = linalg.s2dMatrix(Vec2f32{ .x = 2, .y = 3 });
        const v2 = linalg.Mat4x4f32.mulVec(sc, @Vector(4, f32){ 1, 1, 0, 1 });
        try std.testing.expect(@abs(v2[0] - 2) < 1e-5);
        try std.testing.expect(@abs(v2[1] - 3) < 1e-5);

        // 4) r2dMatrix(pi/2) 점 (1, 0) → (0, 1)
        const pi_half: f32 = std.math.pi / 2.0;
        const r = linalg.r2dMatrix(pi_half);
        const v3 = linalg.Mat4x4f32.mulVec(r, @Vector(4, f32){ 1, 0, 0, 1 });
        try std.testing.expect(@abs(v3[0] - 0) < 1e-5);
        try std.testing.expect(@abs(v3[1] - 1) < 1e-5);

        // 5) inverse(I) == I
        const inv_id = id.inverse();
        for (0..4) |col| {
            for (0..4) |row| {
                const expected: f32 = if (col == row) 1.0 else 0.0;
                try std.testing.expect(@abs(inv_id.data[col][row] - expected) < 1e-5);
            }
        }

        // 6) inverse * M == I
        const m_test = linalg.srt2dMatrix(
            .{ 5, -3, 1 },
            Vec2f32{ .x = 2, .y = 4 },
            0.7,
        );
        const inv_m = m_test.inverse();
        const product = m_test.mul(inv_m);
        for (0..4) |col| {
            for (0..4) |row| {
                const expected: f32 = if (col == row) 1.0 else 0.0;
                try std.testing.expect(@abs(product.data[col][row] - expected) < 1e-5);
            }
        }

        // 7) matrix multiplication: t * r * s = T*R*S
        const t_mat = linalg.Mat4x4f32.translate(.{ 10, 20, 0 });
        const r_mat = linalg.Mat4x4f32.rotateZ(0.5);
        const s_mat = linalg.Mat4x4f32.scale(.{ 2, 3, 1 });
        const combined = t_mat.mul(r_mat.mul(s_mat));
        const manual = linalg.srt2dMatrix(.{ 10, 20, 0 }, Vec2f32{ .x = 2, .y = 3 }, 0.5);
        for (0..4) |col| {
            for (0..4) |row| {
                try std.testing.expect(@abs(combined.data[col][row] - manual.data[col][row]) < 1e-5);
            }
        }

        // 8) inverse * M * inverse == I (역방향 곱 검증)
        const prod2 = inv_m.mul(m_test);
        for (0..4) |col| {
            for (0..4) |row| {
                const expected: f32 = if (col == row) 1.0 else 0.0;
                try std.testing.expect(@abs(prod2.data[col][row] - expected) < 1e-5);
            }
        }

        // 9) inverse(M) * v = v' where M * v' = v (점 단위 검증)
        const v_test = @Vector(4, f32){ 3, 7, 0, 1 };
        const v_moved = linalg.Mat4x4f32.mulVec(m_test, v_test);
        const v_back = linalg.Mat4x4f32.mulVec(inv_m, v_moved);
        try std.testing.expect(@abs(v_back[0] - v_test[0]) < 1e-5);
        try std.testing.expect(@abs(v_back[1] - v_test[1]) < 1e-5);
        try std.testing.expect(@abs(v_back[2] - v_test[2]) < 1e-5);

        // 10) 다양한 행렬들에 대한 inverse 검증
        const cases = [_]linalg.Mat4x4f32{
            linalg.t2dMatrix(.{ 100, 50, 0 }),
            linalg.s2dMatrix(Vec2f32{ .x = 3, .y = 7 }),
            linalg.r2dMatrix(1.234),
            linalg.srt2dMatrix(.{ 1, 2, 3 }, Vec2f32{ .x = 2, .y = 2 }, 0.5),
            linalg.srtc2dMatrix(.{ 0, 0, 0 }, Vec2f32{ .x = 1, .y = 1 }, 0.0, Vec2f32{ .x = 0.5, .y = 0.5 }),
        };
        for (cases) |m_case| {
            const inv_case = m_case.inverse();
            const check = m_case.mul(inv_case);
            for (0..4) |col| {
                for (0..4) |row| {
                    const expected: f32 = if (col == row) 1.0 else 0.0;
                    try std.testing.expect(@abs(check.data[col][row] - expected) < 1e-4);
                }
            }
        }

        // 11) column-major 표기 일관성: translate(1,2,0) 후 data[3][0]=1, data[3][1]=2
        try std.testing.expect(t_mat.data[3][0] == 10);
        try std.testing.expect(t_mat.data[3][1] == 20);
        try std.testing.expect(t_mat.data[3][2] == 0);
        try std.testing.expect(t_mat.data[3][3] == 1);

        // 12) rotation by π/2 검증: column 0 = {cos, sin, 0, 0}
        const r_pi_2 = linalg.Mat4x4f32.rotateZ(std.math.pi / 2.0);
        try std.testing.expect(@abs(r_pi_2.data[0][0]) < 1e-6);
        try std.testing.expect(@abs(r_pi_2.data[0][1] - 1) < 1e-6);
        try std.testing.expect(@abs(r_pi_2.data[1][0] - -1) < 1e-6);
        try std.testing.expect(@abs(r_pi_2.data[1][1]) < 1e-6);
    }

    // sanity: Circle
    {
        const c = linalg.Circlef32{ .p = Vec2f32{ .x = 0, .y = 0 }, .rectRadius = 10 };
        try std.testing.expect(c.rectRadius == 10);
    }

    // sanity: linesIntersect2
    {
        const result = linalg.linesIntersect2(
            f32,
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 10, .y = 0 },
            Vec2f32{ .x = 5, .y = -5 },
            Vec2f32{ .x = 5, .y = 5 },
            false,
        );
        try std.testing.expect(result[0] == .intersect);
        try std.testing.expect(result[1].x == 5);
        try std.testing.expect(result[1].y == 0);
    }

    // sanity: pointInPolygon
    {
        const poly = [_]Vec2f32{
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 10, .y = 0 },
            Vec2f32{ .x = 10, .y = 10 },
            Vec2f32{ .x = 0, .y = 10 },
        };
        const inside = linalg.pointInPolygon(f32, Vec2f32{ .x = 5, .y = 5 }, &poly);
        try std.testing.expect(inside == .Inside);
        const outside = linalg.pointInPolygon(f32, Vec2f32{ .x = 20, .y = 20 }, &poly);
        try std.testing.expect(outside == .Outside);
    }

    // sanity: polygonSignedArea
    {
        const poly = [_]Vec2f32{
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 10, .y = 0 },
            Vec2f32{ .x = 10, .y = 10 },
            Vec2f32{ .x = 0, .y = 10 },
        };
        const area = linalg.polygonSignedArea(&poly);
        try std.testing.expect(area == 100.0);
    }

    // sanity: BezierKind, evalBezierSegment
    {
        const pts = [4]Vec2f32{
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 5, .y = 10 },
            Vec2f32{ .x = 15, .y = 10 },
            Vec2f32{ .x = 20, .y = 0 },
        };
        const mid = linalg.evalBezierSegment(f32, .Cubic, pts, 0.5);
        try std.testing.expect(mid.x > 0);
        try std.testing.expect(mid.y > 0);
    }

    // sanity: crossProductSign
    {
        const sign = linalg.crossProductSign(f32,
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 10, .y = 0 },
            Vec2f32{ .x = 0, .y = 10 },
        );
        try std.testing.expect(sign > 0);
    }

    // sanity: inCircleTest
    {
        const det = linalg.inCircleTest(f32,
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 10, .y = 0 },
            Vec2f32{ .x = 0, .y = 10 },
            Vec2f32{ .x = 2, .y = 2 },
        );
        try std.testing.expect(det > 0);
    }

    // sanity: xyMirrorPoint
    {
        const mirrored = linalg.xyMirrorPoint(f32,
            Vec2f32{ .x = 5, .y = 5 },
            Vec2f32{ .x = 3, .y = 3 },
        );
        try std.testing.expect(mirrored.x == 7);
        try std.testing.expect(mirrored.y == 7);
    }

    std.debug.print("linalg sanity: OK\n", .{});
}
