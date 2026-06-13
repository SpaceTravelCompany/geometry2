//! path_template.zig — Odin path_template.odin 1:1 포팅.
//! CircleCubicInit, RectLineInit, RoundRectLineInit, EllipseCubicInit.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;
const rect_mod = @import("rect.zig");
const Rect = rect_mod.Rect;

// 4-cubic-Bezier로 원/타원을 근사할 때 사용하는 표준 kappa.
// π/4 ≈ 0.7854… 에서 sin(π/4)*4/3 = 0.5522847498… 이며 Odin 원본과 동일.
const CIRCLE_KAPPA: f64 = 0.55228474983079332144;

// ──────────────────────────────────────────────────────────────────────
//  CircleCubicInit — _center/_r → 12 점 + 12 isCurves bool
//  (12개 점으로 4개의 호를 cubic Bezier로 근사)
// ──────────────────────────────────────────────────────────────────────

pub fn circleCubicInit(comptime T: type, _center: Vec2(T), _r: T) struct {
    pts: [12]Vec2(T),
    isCurves: [12]bool,
} {
    const tt: T = @as(T, @floatCast(CIRCLE_KAPPA)) * _r;
    const cx: T = _center.x;
    const cy: T = _center.y;
    return .{
        .pts = [12]Vec2(T){
            .{ .x = cx - _r, .y = cy },
            .{ .x = cx - _r, .y = cy - tt },
            .{ .x = cx - tt, .y = cy - _r },
            .{ .x = cx, .y = cy - _r },
            .{ .x = cx + tt, .y = cy - _r },
            .{ .x = cx + _r, .y = cy - tt },
            .{ .x = cx + _r, .y = cy },
            .{ .x = cx + _r, .y = cy + tt },
            .{ .x = cx + tt, .y = cy + _r },
            .{ .x = cx, .y = cy + _r },
            .{ .x = cx - tt, .y = cy + _r },
            .{ .x = cx - _r, .y = cy + tt },
        },
        .isCurves = [12]bool{ false, true, true, false, true, true, false, true, true, false, true, true },
    };
}

// ──────────────────────────────────────────────────────────────────────
//  RectLineInit — Rect_ → 4 점 (시계방향)
// ──────────────────────────────────────────────────────────────────────

pub fn rectLineInit(comptime T: type, _rect: Rect(T)) [4]Vec2(T) {
    return [4]Vec2(T){
        .{ .x = _rect.left, .y = _rect.top },
        .{ .x = _rect.left, .y = _rect.bottom },
        .{ .x = _rect.right, .y = _rect.bottom },
        .{ .x = _rect.right, .y = _rect.top },
    };
}

// ──────────────────────────────────────────────────────────────────────
//  RoundRectLineInit — 라운드 사각형 외곽선 (12 점 + 12 isCurves)
//  각 모서리는 quadratic Bezier 1개 (anchor-control-anchor 패턴).
// ──────────────────────────────────────────────────────────────────────

pub fn roundRectLineInit(comptime T: type, _rect: Rect(T), _radius: T) struct {
    pts: [12]Vec2(T),
    isCurves: [12]bool,
} {
    var r = _radius;

    const halfWidth: T = (_rect.right - _rect.left) / 2.0;
    var dh: T = _rect.bottom - _rect.top;
    if (dh < 0) dh = -dh;
    const halfHeight: T = dh / 2.0;
    if (r > halfWidth) r = halfWidth;
    if (r > halfHeight) r = halfHeight;

    const L: T = _rect.left;
    const R: T = _rect.right;
    const rt: T = _rect.top;
    const rb: T = _rect.bottom;

    return .{
        .pts = [12]Vec2(T){
            .{ .x = L + r, .y = rt }, // pt0:  top-left corner start (top edge)
            .{ .x = L, .y = rt }, // pt1:  control (corner point)
            .{ .x = L, .y = rt - r }, // pt2:  top-left corner end (left edge)
            .{ .x = L, .y = rb + r }, // pt3:  bottom-left corner start (left edge)
            .{ .x = L, .y = rb }, // pt4:  control (corner point)
            .{ .x = L + r, .y = rb }, // pt5:  bottom-left corner end (bottom edge)
            .{ .x = R - r, .y = rb }, // pt6:  bottom-right corner start (bottom edge)
            .{ .x = R, .y = rb }, // pt7:  control (corner point)
            .{ .x = R, .y = rb + r }, // pt8:  bottom-right corner end (right edge)
            .{ .x = R, .y = rt - r }, // pt9:  top-right corner start (right edge)
            .{ .x = R, .y = rt }, // pt10: control (corner point)
            .{ .x = R - r, .y = rt }, // pt11: top-right corner end (top edge)
        },
        .isCurves = [12]bool{
            false, // pt0:  anchor
            true, // pt1:  control
            false, // pt2:  anchor
            false, // pt3:  anchor — line from pt2
            true, // pt4:  control
            false, // pt5:  anchor
            false, // pt6:  anchor — line from pt5
            true, // pt7:  control
            false, // pt8:  anchor
            false, // pt9:  anchor — line from pt8
            true, // pt10: control
            false, // pt11: anchor
        },
    };
}

// ──────────────────────────────────────────────────────────────────────
//  EllipseCubicInit — _center/_rxy → 12 점 + 12 isCurves
//  x/y 반경이 다를 수 있음.
// ──────────────────────────────────────────────────────────────────────

pub fn ellipseCubicInit(comptime T: type, _center: Vec2(T), _rxy: Vec2(T)) struct {
    pts: [12]Vec2(T),
    isCurves: [12]bool,
} {
    const ttx: T = @as(T, @floatCast(CIRCLE_KAPPA)) * _rxy.x;
    const tty: T = @as(T, @floatCast(CIRCLE_KAPPA)) * _rxy.y;
    const cx: T = _center.x;
    const cy: T = _center.y;
    const rx: T = _rxy.x;
    const ry: T = _rxy.y;
    return .{
        .pts = [12]Vec2(T){
            .{ .x = cx - rx, .y = cy },
            .{ .x = cx - rx, .y = cy - tty },
            .{ .x = cx - ttx, .y = cy - ry },
            .{ .x = cx, .y = cy - ry },
            .{ .x = cx + ttx, .y = cy - ry },
            .{ .x = cx + rx, .y = cy - tty },
            .{ .x = cx + rx, .y = cy },
            .{ .x = cx + rx, .y = cy + tty },
            .{ .x = cx + ttx, .y = cy + ry },
            .{ .x = cx, .y = cy + ry },
            .{ .x = cx - ttx, .y = cy + ry },
            .{ .x = cx - rx, .y = cy + tty },
        },
        .isCurves = [12]bool{ false, true, true, false, true, true, false, true, true, false, true, true },
    };
}

// ──────────────────────────────────────────────────────────────────────
//  단위 테스트
// ──────────────────────────────────────────────────────────────────────

test "path_template: rectLineInit" {
    const r = rect_mod.rectInit(f32, 1.0, 5.0, 2.0, 7.0);
    const pts = rectLineInit(f32, r);
    try std.testing.expectEqual(@as(f32, 1.0), pts[0].x);
    try std.testing.expectEqual(@as(f32, 2.0), pts[0].y);
    try std.testing.expectEqual(@as(f32, 1.0), pts[1].x);
    try std.testing.expectEqual(@as(f32, 7.0), pts[1].y);
    try std.testing.expectEqual(@as(f32, 5.0), pts[2].x);
    try std.testing.expectEqual(@as(f32, 7.0), pts[2].y);
    try std.testing.expectEqual(@as(f32, 5.0), pts[3].x);
    try std.testing.expectEqual(@as(f32, 2.0), pts[3].y);
}

test "path_template: circleCubicInit" {
    const c = Vec2(f32){ .x = 0, .y = 0 };
    const r: f32 = 10.0;
    const out = circleCubicInit(f32, c, r);
    // 첫 점은 (-10, 0)
    try std.testing.expectEqual(@as(f32, -10.0), out.pts[0].x);
    try std.testing.expectEqual(@as(f32, 0.0), out.pts[0].y);
    // 0번은 anchor
    try std.testing.expectEqual(false, out.isCurves[0]);
    // 1번은 control
    try std.testing.expectEqual(true, out.isCurves[1]);
    // 마지막 점은 (-10, +tt) — 원의 좌하
    try std.testing.expectEqual(@as(f32, -10.0), out.pts[11].x);
    try std.testing.expect(out.pts[11].y > 0.0);
}

test "path_template: ellipseCubicInit" {
    const c = Vec2(f32){ .x = 0, .y = 0 };
    const rxy = Vec2(f32){ .x = 5, .y = 3 };
    const out = ellipseCubicInit(f32, c, rxy);
    // 좌측 끝점 (-5, 0)
    try std.testing.expectEqual(@as(f32, -5.0), out.pts[0].x);
    try std.testing.expectEqual(@as(f32, 0.0), out.pts[0].y);
    // 우측 끝점 (5, 0)
    try std.testing.expectEqual(@as(f32, 5.0), out.pts[6].x);
    try std.testing.expectEqual(@as(f32, 0.0), out.pts[6].y);
    // 상단 중간 (0, -3)
    try std.testing.expectEqual(@as(f32, 0.0), out.pts[3].x);
    try std.testing.expectEqual(@as(f32, -3.0), out.pts[3].y);
}

test "path_template: roundRectLineInit" {
    const r = rect_mod.rectInit(f32, 0.0, 10.0, 0.0, 10.0);
    const out = roundRectLineInit(f32, r, 2.0);
    // halfWidth = halfHeight = 5, r=2 (조정 없음)
    // pt0 = (L+r, rt) = (2, 0)
    try std.testing.expectEqual(@as(f32, 2.0), out.pts[0].x);
    try std.testing.expectEqual(@as(f32, 0.0), out.pts[0].y);
    // pt1 = (L, rt) = (0, 0) — control
    try std.testing.expectEqual(true, out.isCurves[1]);
    // isCurves 패턴
    try std.testing.expectEqual(false, out.isCurves[0]);
    try std.testing.expectEqual(false, out.isCurves[2]);
    try std.testing.expectEqual(false, out.isCurves[3]);
    try std.testing.expectEqual(true, out.isCurves[4]);
}

test "path_template: roundRectLineInit clamps radius to half-width" {
    // r=100 > halfWidth(5) → r=5
    const r = rect_mod.rectInit(f32, 0.0, 10.0, 0.0, 10.0);
    const out = roundRectLineInit(f32, r, 100.0);
    // pt0 = (L+r, rt) = (5, 0) after clamp
    try std.testing.expectEqual(@as(f32, 5.0), out.pts[0].x);
}
