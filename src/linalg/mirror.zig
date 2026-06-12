//! mirror.zig — 대칭/반전 연산.
//! xyMirrorPoint, OppPolyOrientation.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;
const polygon = @import("polygon.zig");
const PolyOrientation = polygon.PolyOrientation;

// ──────────────────────────────────────────────────────────────────────
//  xyMirrorPoint
// ──────────────────────────────────────────────────────────────────────

pub fn xyMirrorPoint(comptime T: type, pivot: Vec2(T), target: Vec2(T)) Vec2(T) {
    const two: T = 2.0;
    return Vec2(T){
        .x = two * pivot.x - target.x,
        .y = two * pivot.y - target.y,
    };
}

// ──────────────────────────────────────────────────────────────────────
//  OppPolyOrientation
// ──────────────────────────────────────────────────────────────────────

pub inline fn oppPolyOrientation(ccw: PolyOrientation) PolyOrientation {
    return if (ccw == .Clockwise) .CounterClockwise else .Clockwise;
}
