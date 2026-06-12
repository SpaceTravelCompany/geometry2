//! polygon.zig — 폴리곤 연산.
//! PolygonOverlapsPolygon, PointInPolygon, CenterPointInPolygon,
//! GetPolygonOrientation, PolygonSignedArea, LineInPolygon.
//! 또한 PolyOrientation enum, IsPointOnSegment 내부 함수 포함.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;
const Vec2f32 = linalg.Vec2f32;
const rect = @import("rect.zig");
const PointInPolygonResult = rect.PointInPolygonResult;
const lines = @import("lines.zig");
const linesIntersect2 = lines.linesIntersect2;
const linesIntersect3 = lines.linesIntersect3;
const crossProductSign = lines.crossProductSign;
const epsilon = linalg.epsilon;

// ──────────────────────────────────────────────────────────────────────
//  PolyOrientation
// ──────────────────────────────────────────────────────────────────────

pub const PolyOrientation = enum {
    Clockwise,
    CounterClockwise,
};

// ──────────────────────────────────────────────────────────────────────
//  PolygonOverlapsPolygon
// ──────────────────────────────────────────────────────────────────────

pub fn polygonOverlapsPolygon(comptime T: type, poly1: []const Vec2(T), poly2: []const Vec2(T)) bool {
    if (poly1.len < 3 or poly2.len < 3) return false;
    for (poly1) |p| {
        if (pointInPolygon(T, p, poly2) == .Inside) return true;
    }
    for (poly2) |p| {
        if (pointInPolygon(T, p, poly1) == .Inside) return true;
    }
    for (0..poly1.len) |i| {
        const a1 = poly1[i];
        const b1 = poly1[(i + 1) % poly1.len];
        for (0..poly2.len) |j| {
            const a2 = poly2[j];
            const b2 = poly2[(j + 1) % poly2.len];
            if (linesIntersect3(T, a1, b1, a2, b2, false) == .intersect) return true;
        }
    }
    return false;
}

// ──────────────────────────────────────────────────────────────────────
//  isPointOnSegment (내부)
// ──────────────────────────────────────────────────────────────────────

fn isPointOnSegment(comptime T: type, p: Vec2(T), p1: Vec2(T), p2: Vec2(T)) bool {
    return crossProductSign(T, p1, p2, p) == 0 and
        p.x >= (if (p1.x < p2.x) p1.x else p2.x) and
        p.x <= (if (p1.x > p2.x) p1.x else p2.x) and
        p.y >= (if (p1.y < p2.y) p1.y else p2.y) and
        p.y <= (if (p1.y > p2.y) p1.y else p2.y);
}

// ──────────────────────────────────────────────────────────────────────
//  PointInPolygon
// ──────────────────────────────────────────────────────────────────────

pub fn pointInPolygon(comptime T: type, p: Vec2(T), polygon: []const Vec2(T)) PointInPolygonResult {
    var windingNumber: i32 = 0;
    for (0..polygon.len) |i| {
        const p1 = polygon[i];
        const p2 = polygon[(i + 1) % polygon.len];
        if (isPointOnSegment(T, p, p1, p2)) return .On;

        if (p1.y <= p.y) {
            if (p2.y > p.y and crossProductSign(T, p1, p2, p) > 0) windingNumber += 1;
        } else {
            if (p2.y <= p.y and crossProductSign(T, p1, p2, p) < 0) windingNumber -= 1;
        }
    }
    return if (windingNumber != 0) .Inside else .Outside;
}

// ──────────────────────────────────────────────────────────────────────
//  CenterPointInPolygon
// ──────────────────────────────────────────────────────────────────────

pub fn centerPointInPolygon(comptime T: type, polygon: []const Vec2(T)) Vec2(T) {
    var area: f32 = 0;
    var p = Vec2(T){ .x = 0, .y = 0 };
    for (0..polygon.len) |i| {
        const j = (i + 1) % polygon.len;
        const factor = linalg.vec2Cross(T, polygon[i], polygon[j]);
        area += @as(f32, @floatCast(factor));
        const sum = linalg.vec2Add(T, polygon[i], polygon[j]);
        const sc = linalg.vec2Scale(T, sum, factor);
        p = linalg.vec2Add(T, p, sc);
    }
    area = area / 2 * 6;
    p.x /= @as(T, @floatCast(area));
    p.y /= @as(T, @floatCast(area));
    return p;
}

// ──────────────────────────────────────────────────────────────────────
//  GetPolygonOrientation
// ──────────────────────────────────────────────────────────────────────

pub fn getPolygonOrientation(comptime T: type, polygon: []const Vec2(T)) PolyOrientation {
    const zero: T = 0;
    var res: T = zero;
    for (0..polygon.len) |i| {
        const j = (i + 1) % polygon.len;
        const factor = (polygon[j].x - polygon[i].x) * (polygon[j].y + polygon[i].y);
        res = res + factor;
    }
    return if (res > zero) .Clockwise else .CounterClockwise;
}

// ──────────────────────────────────────────────────────────────────────
//  PolygonSignedArea
// ──────────────────────────────────────────────────────────────────────

pub fn polygonSignedArea(polygon: []const Vec2f32) f32 {
    const n = polygon.len;
    if (n < 3) return 0;
    var area: f32 = 0;
    for (0..n) |i| {
        const j = (i + 1) % n;
        area += polygon[i].x * polygon[j].y - polygon[j].x * polygon[i].y;
    }
    return area * 0.5;
}

// ──────────────────────────────────────────────────────────────────────
//  LineInPolygon
// ──────────────────────────────────────────────────────────────────────

pub fn lineInPolygon(comptime T: type, a: Vec2(T), b: Vec2(T), polygon: []const Vec2(T), options: struct { checkInsideLine: bool = true }) bool {
    if (options.checkInsideLine and pointInPolygon(T, a, polygon) != .Outside) return true;

    for (0..polygon.len) |i| {
        const j = (i + 1) % polygon.len;
        const result = linesIntersect2(T, polygon[i], polygon[j], a, b, false);
        if (result[0] == .intersect) {
            const resPt = result[1];
            const eps = epsilon(T) * @as(T, 16);
            const sameA = @abs(a.x - resPt.x) <= eps and @abs(a.y - resPt.y) <= eps;
            const sameB = @abs(b.x - resPt.x) <= eps and @abs(b.y - resPt.y) <= eps;
            if (sameA or sameB) continue;
            return true;
        }
    }
    return false;
}
