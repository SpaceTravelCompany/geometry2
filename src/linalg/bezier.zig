//! bezier.zig — 베지어 곡선 평가.
//! Odin bezier_intersect.odin의 BezierKind, EvalBezier, EvalBezierTangent,
//! Odin linalg_ex.odin의 evalBezierSegment, CvtQuadraticToCubic0, CvtQuadraticToCubic1.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;

// ──────────────────────────────────────────────────────────────────────
//  BezierKind
// ──────────────────────────────────────────────────────────────────────

pub const BezierKind = enum(u8) {
    Line,
    Quad,
    Cubic,
};

// ──────────────────────────────────────────────────────────────────────
//  EvalBezier
// ──────────────────────────────────────────────────────────────────────

pub fn evalBezier(comptime T: type, kind: BezierKind, pts: [4]Vec2(T), t: T) Vec2(T) {
    const u: T = 1 - t;
    const two: T = 2;
    const three: T = 3;
    switch (kind) {
        .Line => {
            const p0 = pts[0];
            const p1 = pts[1];
            return Vec2(T){
                .x = u * p0.x + t * p1.x,
                .y = u * p0.y + t * p1.y,
            };
        },
        .Quad => {
            const p0 = pts[0];
            const p1 = pts[1];
            const p2 = pts[2];
            const uu = u * u;
            const tt = t * t;
            const ut2 = two * u * t;
            return Vec2(T){
                .x = uu * p0.x + ut2 * p1.x + tt * p2.x,
                .y = uu * p0.y + ut2 * p1.y + tt * p2.y,
            };
        },
        .Cubic => {
            const p0 = pts[0];
            const p1 = pts[1];
            const p2 = pts[2];
            const p3 = pts[3];
            const uu = u * u;
            const tt = t * t;
            const uuu = uu * u;
            const ttt = tt * t;
            const uut3 = three * uu * t;
            const utt3 = three * u * tt;
            return Vec2(T){
                .x = uuu * p0.x + uut3 * p1.x + utt3 * p2.x + ttt * p3.x,
                .y = uuu * p0.y + uut3 * p1.y + utt3 * p2.y + ttt * p3.y,
            };
        },
    }
}

// ──────────────────────────────────────────────────────────────────────
//  EvalBezierTangent
// ──────────────────────────────────────────────────────────────────────

pub fn evalBezierTangent(comptime T: type, kind: BezierKind, pts: [4]Vec2(T), t: T) Vec2(T) {
    const one: T = 1;
    const u = one - t;
    const two: T = 2;
    const three: T = 3;
    const six: T = 6;
    switch (kind) {
        .Line => {
            const p0 = pts[0];
            const p1 = pts[1];
            return Vec2(T){ .x = p1.x - p0.x, .y = p1.y - p0.y };
        },
        .Quad => {
            const p0 = pts[0];
            const p1 = pts[1];
            const p2 = pts[2];
            return Vec2(T){
                .x = two * u * (p1.x - p0.x) + two * t * (p2.x - p1.x),
                .y = two * u * (p1.y - p0.y) + two * t * (p2.y - p1.y),
            };
        },
        .Cubic => {
            const p0 = pts[0];
            const p1 = pts[1];
            const p2 = pts[2];
            const p3 = pts[3];
            const uu = u * u;
            const tt = t * t;
            const ut6 = six * u * t;
            return Vec2(T){
                .x = three * uu * (p1.x - p0.x) + ut6 * (p2.x - p1.x) + three * tt * (p3.x - p2.x),
                .y = three * uu * (p1.y - p0.y) + ut6 * (p2.y - p1.y) + three * tt * (p3.y - p2.y),
            };
        },
    }
}

// ──────────────────────────────────────────────────────────────────────
//  evalBezierSegment
// ──────────────────────────────────────────────────────────────────────

pub fn evalBezierSegment(comptime T: type, kind: BezierKind, pts: [4]Vec2(T), t: T) Vec2(T) {
    switch (kind) {
        .Line => {
            const u: T = 1 - t;
            return Vec2(T){
                .x = u * pts[0].x + t * pts[1].x,
                .y = u * pts[0].y + t * pts[1].y,
            };
        },
        .Quad => return evalBezier(T, kind, pts, t),
        .Cubic => return evalBezier(T, kind, pts, t),
    }
}

// ──────────────────────────────────────────────────────────────────────
//  CvtQuadraticToCubic0
// ──────────────────────────────────────────────────────────────────────

pub inline fn cvtQuadraticToCubic0(comptime T: type, _start: Vec2(T), _control: Vec2(T)) Vec2(T) {
    const f: T = 2.0 / 3.0;
    return Vec2(T){
        .x = _start.x + f * (_control.x - _start.x),
        .y = _start.y + f * (_control.y - _start.y),
    };
}

// ──────────────────────────────────────────────────────────────────────
//  CvtQuadraticToCubic1
// ──────────────────────────────────────────────────────────────────────

pub inline fn cvtQuadraticToCubic1(comptime T: type, _end: Vec2(T), _control: Vec2(T)) Vec2(T) {
    return cvtQuadraticToCubic0(T, _end, _control);
}
