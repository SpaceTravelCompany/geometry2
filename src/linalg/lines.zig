//! lines.zig — 선분 / 점 연산.
//! LinesIntersect2, LinesIntersect3, PointInLine, PointDeltaInLine,
//! PointInVector, PointLineLeftOrRight, CrossProductSign, DotProduct,
//! NearestPointBetweenPointAndLine, InCircleTest, GetAngle,
//! SubdivLine, SubdivQuadraticBezier, SubdivCubicBezier, ShortestLength2Line.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2 = linalg.Vec2;
const Vec2f32 = linalg.Vec2f32;
const epsilon = linalg.epsilon;
const vec2Add = linalg.vec2Add;
const vec2Sub = linalg.vec2Sub;
const vec2Scale = linalg.vec2Scale;
const vec2Dot = linalg.vec2Dot;
const vec2Lerp = linalg.vec2Lerp;
const vec2Cross = linalg.vec2Cross;
const vec2Length2 = linalg.vec2Length2;
const lerp = linalg.lerp;

// ──────────────────────────────────────────────────────────────────────
//  IntersectKind
// ──────────────────────────────────────────────────────────────────────

pub const IntersectKind = enum(u8) {
    none,
    collinear,
    intersect,
};

// ──────────────────────────────────────────────────────────────────────
//  LinesIntersect2 — 두 선분 교차 검사 + 교차점 반환
// ──────────────────────────────────────────────────────────────────────

pub fn linesIntersect2(
    comptime T: type,
    a1: Vec2(T),
    a2: Vec2(T),
    b1: Vec2(T),
    b2: Vec2(T),
    checkIsTouching: bool,
) struct { IntersectKind, Vec2(T) } {
    if (checkIsTouching) {
        const sameAB1 = a1.x == b1.x and a1.y == b1.y;
        const sameAB2 = a1.x == b2.x and a1.y == b2.y;
        const sameA2B1 = a2.x == b1.x and a2.y == b1.y;
        const sameA2B2 = a2.x == b2.x and a2.y == b2.y;
        if (sameAB1 or sameAB2) return .{ .none, a1 };
        if (sameA2B1 or sameA2B2) return .{ .none, a2 };
    }

    const zero: T = 0;
    const den = (b2.y - b1.y) * (a2.x - a1.x) - (b2.x - b1.x) * (a2.y - a1.y);
    if (den == zero) {
        // Odin 의 `return .collinear, {}` 와 동등: zero-init Vec2 반환.
        return .{ .collinear, Vec2(T){ .x = 0, .y = 0 } };
    }

    const ua = (b2.x - b1.x) * (a1.y - b1.y) - (b2.y - b1.y) * (a1.x - b1.x);
    const ub = (a2.x - a1.x) * (a1.y - b1.y) - (a2.y - a1.y) * (a1.x - b1.x);

    const resDen = if (den > zero)
        ua >= zero and ub >= zero and ua <= den and ub <= den
    else
        ua >= den and ub >= den and ua <= zero and ub <= zero;

    const t = ua / den;
    return .{
        if (resDen) .intersect else .none,
        Vec2(T){ .x = a1.x + t * (a2.x - a1.x), .y = a1.y + t * (a2.y - a1.y) },
    };
}

// ──────────────────────────────────────────────────────────────────────
//  LinesIntersect3 — 두 선분 교차 여부만 반환
// ──────────────────────────────────────────────────────────────────────

pub fn linesIntersect3(
    comptime T: type,
    a1: Vec2(T),
    a2: Vec2(T),
    b1: Vec2(T),
    b2: Vec2(T),
    checkIsTouching: bool,
) IntersectKind {
    const sameA1B1 = a1.x == b1.x and a1.y == b1.y;
    const sameA2B1 = a2.x == b1.x and a2.y == b1.y;
    const sameA1B2 = a1.x == b2.x and a1.y == b2.y;
    const sameA2B2 = a2.x == b2.x and a2.y == b2.y;
    if (checkIsTouching and (sameA1B1 or sameA2B1 or sameA1B2 or sameA2B2)) return .none;

    const zero: T = 0;
    const den = (b2.y - b1.y) * (a2.x - a1.x) - (b2.x - b1.x) * (a2.y - a1.y);
    if (den == zero) return .collinear;
    const ua = (b2.x - b1.x) * (a1.y - b1.y) - (b2.y - b1.y) * (a1.x - b1.x);
    const ub = (a2.x - a1.x) * (a1.y - b1.y) - (a2.y - a1.y) * (a1.x - b1.x);
    const resDen = if (den > zero)
        ua >= zero and ub >= zero and ua <= den and ub <= den
    else
        ua >= den and ub >= den and ua <= zero and ub <= zero;
    return if (resDen) .intersect else .none;
}

// ──────────────────────────────────────────────────────────────────────
//  PointInLine
// ──────────────────────────────────────────────────────────────────────

pub fn pointInLine(comptime T: type, p: Vec2(T), l0: Vec2(T), l1: Vec2(T)) struct { bool, T } {
    const minX: T = if (l0.x < l1.x) l0.x else l1.x;
    const maxX: T = if (l0.x > l1.x) l0.x else l1.x;
    const minY: T = if (l0.y < l1.y) l0.y else l1.y;
    const maxY: T = if (l0.y > l1.y) l0.y else l1.y;
    const a_coeff = (l0.y - l1.y) / (l0.x - l1.x);
    const b_coeff = l0.y - a_coeff * l0.x;
    const pY = a_coeff * p.x + b_coeff;
    const inBbox = p.x >= minX and p.x <= maxX and p.y >= minY and p.y <= maxY;
    const t_val = (p.x - minX) / (maxX - minX);
    const onLine = @abs(p.y - pY) <= epsilon(T) * @as(T, 16);
    return .{ onLine and inBbox, t_val };
}

// ──────────────────────────────────────────────────────────────────────
//  PointDeltaInLine
// ──────────────────────────────────────────────────────────────────────

pub fn pointDeltaInLine(comptime T: type, p: Vec2(T), l0: Vec2(T), l1: Vec2(T)) T {
    const pp = nearestPointBetweenPointAndLine(T, p, l0, l1);
    // lerp scalar: l0.x → l1.x at t = pp.x (projection parameter)
    return lerp(l0.x, l1.x, pp.x);
}

// ──────────────────────────────────────────────────────────────────────
//  PointInVector
// ──────────────────────────────────────────────────────────────────────

pub fn pointInVector(comptime T: type, p: Vec2(T), v0: Vec2(T), v1: Vec2(T)) struct { bool, T } {
    const zero: T = 0;
    const a_coeff = v1.y - v0.y;
    const b_coeff = v0.x - v1.x;
    const c_coeff = v1.x * v0.y - v0.x * v1.y;
    const res = a_coeff * p.x + b_coeff * p.y + c_coeff;
    return .{ @abs(res - zero) <= epsilon(T) * @as(T, 16), res };
}

// ──────────────────────────────────────────────────────────────────────
//  PointLineLeftOrRight
// ──────────────────────────────────────────────────────────────────────

pub inline fn pointLineLeftOrRight(comptime T: type, p: Vec2(T), l0: Vec2(T), l1: Vec2(T)) T {
    return (l1.x - l0.x) * (p.y - l0.y) - (p.x - l0.x) * (l1.y - l0.y);
}

// ──────────────────────────────────────────────────────────────────────
//  CrossProductSign
// ──────────────────────────────────────────────────────────────────────

pub fn crossProductSign(comptime T: type, p1: Vec2(T), p2: Vec2(T), p3: Vec2(T)) i32 {
    const a = p2.x - p1.x;
    const b = p3.y - p2.y;
    const c = p2.y - p1.y;
    const d = p3.x - p2.x;
    const ab = a * b;
    const cd = c * d;
    if (ab > cd) return 1;
    if (ab < cd) return -1;
    return 0;
}

// ──────────────────────────────────────────────────────────────────────
//  DotProduct
// ──────────────────────────────────────────────────────────────────────

pub fn dotProduct(comptime T: type, p1: Vec2(T), p2: Vec2(T), p3: Vec2(T)) T {
    const a = p2.x - p1.x;
    const b = p3.x - p2.x;
    const c = p2.y - p1.y;
    const d = p3.y - p2.y;
    return a * b + c * d;
}

// ──────────────────────────────────────────────────────────────────────
//  NearestPointBetweenPointAndLine
// ──────────────────────────────────────────────────────────────────────

pub fn nearestPointBetweenPointAndLine(comptime T: type, p: Vec2(T), l0: Vec2(T), l1: Vec2(T)) Vec2(T) {
    const AB = vec2Sub(T, l1, l0);
    const AC = vec2Sub(T, p, l0);
    const t = vec2Dot(T, AB, AC) / vec2Dot(T, AB, AB);
    return vec2Add(T, l0, vec2Scale(T, AB, t));
}

// ──────────────────────────────────────────────────────────────────────
//  InCircleTest
// ──────────────────────────────────────────────────────────────────────

pub fn inCircleTest(comptime T: type, ptA: Vec2(T), ptB: Vec2(T), ptC: Vec2(T), ptD: Vec2(T)) T {
    const m00 = ptA.x - ptD.x;
    const m01 = ptA.y - ptD.y;
    const m02 = m00 * m00 + m01 * m01;
    const m10 = ptB.x - ptD.x;
    const m11 = ptB.y - ptD.y;
    const m12 = m10 * m10 + m11 * m11;
    const m20 = ptC.x - ptD.x;
    const m21 = ptC.y - ptD.y;
    const m22 = m20 * m20 + m21 * m21;
    return m00 * (m11 * m22 - m21 * m12) - m10 * (m01 * m22 - m21 * m02) + m20 * (m01 * m12 - m11 * m02);
}

// ──────────────────────────────────────────────────────────────────────
//  GetAngle
// ──────────────────────────────────────────────────────────────────────

pub fn getAngle(comptime T: type, a: Vec2(T), b: Vec2(T), c: Vec2(T)) T {
    const abx = b.x - a.x;
    const aby = b.y - a.y;
    const bcx = b.x - c.x;
    const bcy = b.y - c.y;
    const dp = abx * bcx + aby * bcy;
    const cp = abx * bcy - aby * bcx;
    return std.math.atan2(cp, dp);
}

// ──────────────────────────────────────────────────────────────────────
//  SubdivLine
// ──────────────────────────────────────────────────────────────────────

pub fn subdivLine(comptime T: type, pts: [2]Vec2(T), subdiv: T) Vec2(T) {
    return vec2Lerp(T, pts[0], pts[1], subdiv);
}

// ──────────────────────────────────────────────────────────────────────
//  SubdivQuadraticBezier
// ──────────────────────────────────────────────────────────────────────

pub fn subdivQuadraticBezier(
    comptime T: type,
    pts: [3]Vec2(T),
    subdiv: T,
) struct { Vec2(T), Vec2(T), Vec2(T) } {
    const pt1 = vec2Lerp(T, pts[0], pts[1], subdiv);
    const pt2 = vec2Lerp(T, pts[1], pts[2], subdiv);
    const pt12 = vec2Lerp(T, pt1, pt2, subdiv);
    return .{ pt1, pt12, pt2 };
}

// ──────────────────────────────────────────────────────────────────────
//  SubdivCubicBezier
// ──────────────────────────────────────────────────────────────────────

pub fn subdivCubicBezier(
    comptime T: type,
    pts: [4]Vec2(T),
    subdiv: T,
) struct { Vec2(T), Vec2(T), Vec2(T), Vec2(T), Vec2(T) } {
    const p01 = vec2Lerp(T, pts[0], pts[1], subdiv);
    const p12 = vec2Lerp(T, pts[1], pts[2], subdiv);
    const p23 = vec2Lerp(T, pts[2], pts[3], subdiv);
    const p012 = vec2Lerp(T, p01, p12, subdiv);
    const p123 = vec2Lerp(T, p12, p23, subdiv);
    const c0 = p01;
    const c1 = p012;
    const m = vec2Lerp(T, p012, p123, subdiv);
    const d0 = p123;
    const d1 = p23;
    return .{ c0, c1, m, d0, d1 };
}

// ──────────────────────────────────────────────────────────────────────
//  ShortestLength2Line
// ──────────────────────────────────────────────────────────────────────

pub fn shortestLength2Line(comptime T: type, pt: Vec2(T), l1: Vec2(T), l2: Vec2(T)) T {
    const zero: T = 0;
    const dx = l2.x - l1.x;
    const dy = l2.y - l1.y;
    const ax = pt.x - l1.x;
    const ay = pt.y - l1.y;
    const qNum = ax * dx + ay * dy;
    const denom = dx * dx + dy * dy;
    if (qNum < zero) {
        return ax * ax + ay * ay;
    } else if (qNum > denom) {
        const bx = pt.x - l2.x;
        const by = pt.y - l2.y;
        return bx * bx + by * by;
    } else {
        const cross = ax * dy - dx * ay;
        return (cross * cross) / denom;
    }
}
