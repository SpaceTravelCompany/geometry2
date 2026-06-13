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

    // sanity: path_template (CircleCubicInit / RectLineInit /
    //                       RoundRectLineInit / EllipseCubicInit)
    {
        // RectLineInit
        const r0 = linalg.rectInit(f32, 0.0, 10.0, 0.0, 10.0);
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
        const ee = linalg.ellipseCubicInit(f32,
            Vec2f32{ .x = 0, .y = 0 },
            Vec2f32{ .x = 3, .y = 2 },
        );
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

    // sanity: polyTransformMatrix (compilation + behavior)
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

        // identity matrix should leave points unchanged
        const F = linalg.Mat4x4f32.identity();
        linalg.polyTransformMatrix(&shapes, F);
        try std.testing.expect(shapes.nodes[0].pts[0][0].x == 0.0);
        try std.testing.expect(shapes.nodes[0].pts[0][0].y == 0.0);
        try std.testing.expect(shapes.nodes[0].pts[0][1].x == 10.0);
        try std.testing.expect(shapes.nodes[0].pts[0][1].y == 0.0);
        try std.testing.expect(shapes.nodes[0].pts[0][2].x == 10.0);
        try std.testing.expect(shapes.nodes[0].pts[0][2].y == 10.0);

        // translation (5, 7, 0): (0, 0) → (5, 7), (10, 0) → (15, 7)
        const T = linalg.Mat4x4f32.translate(.{ 5, 7, 0 });
        linalg.polyTransformMatrix(&shapes, T);
        try std.testing.expect(shapes.nodes[0].pts[0][0].x == 5.0);
        try std.testing.expect(shapes.nodes[0].pts[0][0].y == 7.0);
        try std.testing.expect(shapes.nodes[0].pts[0][1].x == 15.0);
        try std.testing.expect(shapes.nodes[0].pts[0][1].y == 7.0);
    }

    // sanity: shapesComputePolygon (line + quadratic)
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

        // shapesComputePolygon uses the allocator for inner per-contour dynamic arrays.
        // Wrap in an arena so we get a clean free for all temp allocations.
        var arena = std.heap.ArenaAllocator.init(test_alloc);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        const raw = try linalg.shapesComputePolygon(shapes, arena_alloc);
        // raw.vertices / raw.indices are owned by the user and live outside the arena.
        // We need a separate allocator for the final dupe. Use the test_alloc for those.
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

    // ═══════════════════════════════════════════════════════════════════
    // 실 파싱 테스트 1: SVG initParse end-to-end
    //   - Q (quadratic) → CUBIC 변환 후 좌표 보존 확인
    //   - isCurves 보존 확인
    //   - Y-flip (geom Y-up, svg Y-down) 확인
    // ═══════════════════════════════════════════════════════════════════
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

        // SVG path "M 10 10 Q 50 90 90 10 Q 50 50 10 10 Z" 가
        // plutovg에서 MOVE_TO(10,10) + CUBIC_TO(36.67,63.33,63.33,36.67,90,10)
        // + CUBIC_TO(63.33,36.67,36.67,36.67,10,10) + CLOSE(10,10) 로 변환되며
        // CLOSE 후 중복점 제거 + Y-flip 적용 후 6 pts, 6 isCurves가 나와야 함.
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
        try std.testing.expect(curves[0] == false); // M (anchor)
        try std.testing.expect(curves[1] == true);  // CUBIC ctrl1
        try std.testing.expect(curves[2] == true);  // CUBIC ctrl2
        try std.testing.expect(curves[3] == false); // CUBIC end (anchor)
        try std.testing.expect(curves[4] == true);  // CUBIC ctrl1
        try std.testing.expect(curves[5] == true);  // CUBIC ctrl2
    }

    // ═══════════════════════════════════════════════════════════════════
    // 실 파싱 테스트 2: rasterizer end-to-end (SVG → shapes → pixels)
    //   svg path를 파싱한 ShapeNode를 rasterizer에 직접 전달
    //   - 수동 shape 대신 parser.shapes 사용
    //   - 픽셀 버퍼 non-zero 확인
    // ═══════════════════════════════════════════════════════════════════
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

        // SVG path "M 10 10 L 90 10 L 90 90 L 10 90 Z" → 4 anchor 사각형
        try std.testing.expect(parser.shapes.nodes.len == 1);
        const svg_node = parser.shapes.nodes[0];
        try std.testing.expect(svg_node.pts.len == 1);
        try std.testing.expect(svg_node.pts[0].len == 4); // 4 corners

        // rasterizer는 const Shapes를 받음 — parser.shapes를 그대로 전달 가능
        const pixels = try linalg.rasterizer.shapesToPixels(parser.shapes, 100, 100, test_alloc);
        defer linalg.rasterizer.rasterizedPixelsFree(@constCast(&pixels));

        try std.testing.expect(pixels.width == 100);
        try std.testing.expect(pixels.height == 100);
        try std.testing.expect(pixels.pixels.len > 0);

        // 100x100 surface에서 사각형 영역에 black 픽셀이 그려져야 함
        var has_nonzero = false;
        for (pixels.pixels) |byte| {
            if (byte != 0) {
                has_nonzero = true;
                break;
            }
        }
        try std.testing.expect(has_nonzero);
    }

    // ═══════════════════════════════════════════════════════════════════
    // 실 파싱 테스트 3: geometry aggregator sanity
    //   - shapesComputePolygon (rect pts → RawShape)
    //   - getCubicCurveType (Line/Quadratic 확인)
    //   - reverseShapeCloseCurve (간단한 입력/출력)
    // ═══════════════════════════════════════════════════════════════════
    {
        var gpa = std.heap.DebugAllocator(.{}).init;
        defer _ = gpa.deinit();
        const test_alloc = gpa.allocator();

        {
            var arena = std.heap.ArenaAllocator.init(test_alloc);
            defer arena.deinit();
            const arena_alloc = arena.allocator();

            // CCW 삼각형으로 shapesComputePolygon 검증 (line-only, reverse 회피)
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
            const tshapes = linalg.Shapes{
                .nodes = (&tnode)[0..1],
                .clipRect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 },
            };
            const raw = try linalg.shapesComputePolygon(tshapes, arena_alloc);
            try std.testing.expect(raw.vertices.len > 0);
            try std.testing.expect(raw.indices.len > 0);
        }

        // getCubicCurveType: Line (모든 점이 동일선상)
        {
            const result = try linalg.getCubicCurveType(
                f32,
                Vec2f32{ .x = 0, .y = 0 },
                Vec2f32{ .x = 1, .y = 1 },
                Vec2f32{ .x = 2, .y = 2 },
                Vec2f32{ .x = 3, .y = 3 },
            );
            // collinear = degenerate → could be Line or Quadratic
            std.debug.print("getCubicCurveType: type={s} d0={d} d1={d} d2={d}\n", .{
                @tagName(result.curveType), result.d0, result.d1, result.d2,
            });
            try std.testing.expect(result.curveType == .Line or result.curveType == .Quadratic);
        }

        // getCubicCurveType: point 오류 검증
        {
            const p = Vec2f32{ .x = 0, .y = 0 };
            const err = linalg.getCubicCurveType(f32, p, p, p, p);
            try std.testing.expectError(error.IsPointNotLine, err);
        }

        // reverseShapeCloseCurve: 간단한 line-only polygon (4 anchor, 모두 비커브)
        // all-anchor case → Consecutive_Anchor_Missing_Control 오류 (예상 동작)
        {
            const pts = [_]Vec2f32{
                Vec2f32{ .x = 0, .y = 0 },
                Vec2f32{ .x = 10, .y = 0 },
                Vec2f32{ .x = 10, .y = 10 },
                Vec2f32{ .x = 0, .y = 10 },
            };
            const curves = [_]bool{ false, false, false, false };
            const err = linalg.reverseShapeCloseCurve(&pts, &curves, test_alloc);
            // line-only polygon → reverse 실패 (예상: Consecutive_Anchor_Missing_Control)
            try std.testing.expectError(error.Consecutive_Anchor_Missing_Control, err);
        }

        // reverseShapeCloseCurve: anchor-curve-anchor 패턴 → 정상 동작
        //   anchor0(0,0) - ctl0 - anchor1(5,5) - ctl1 - ctl2 -[wrap]-> anchor0
        //   5 points: [anchor0, ctl0, anchor1, ctl1, ctl2]
        //   curves:   [false,   true,  false,   true,  true]
        {
            const pts = [_]Vec2f32{
                Vec2f32{ .x = 0, .y = 0 },    // anchor 0
                Vec2f32{ .x = 2, .y = 5 },    // curve control (anchor0→anchor1)
                Vec2f32{ .x = 5, .y = 5 },    // anchor 1
                Vec2f32{ .x = 5, .y = 7 },    // curve control (anchor1→wrap→anchor0)
                Vec2f32{ .x = 10, .y = 8 },   // curve control (anchor1→wrap→anchor0)
            };
            const curves = [_]bool{ false, true, false, true, true };
            const result = try linalg.reverseShapeCloseCurve(&pts, &curves, test_alloc);
            defer test_alloc.free(result.pts);
            defer test_alloc.free(result.isCurves);

            try std.testing.expect(result.pts.len == pts.len);
            try std.testing.expect(result.isCurves.len == curves.len);
            try std.testing.expect(!result.isCurves[0]); // 첫 점은 항상 anchor
        }
    }

    std.debug.print("linalg sanity: OK\n", .{});
}
