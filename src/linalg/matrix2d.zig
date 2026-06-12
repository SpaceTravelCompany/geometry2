//! matrix2d.zig — 2D 변환 행렬 생성 함수.
//! srtc2dMatrix, srt2dMatrix, st2dMatrix, rt2dMatrix, t2dMatrix,
//! src2dMatrix, sr2dMatrix, s2dMatrix, r2dMatrix, srt2dMatrix2, sr2dMatrix2.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2f32 = linalg.Vec2f32;
const Vec3f32 = linalg.Vec3f32;
const Vec4f32 = linalg.Vec4f32;
const Mat4x4f32 = linalg.Mat4x4f32;

// ──────────────────────────────────────────────────────────────────────
//  srtc2dMatrix — Scale + Rotate + Translate, center pivot
// ──────────────────────────────────────────────────────────────────────

pub fn srtc2dMatrix(t: Vec3f32, s: Vec2f32, r: f32, cp: Vec2f32) Mat4x4f32 {
    const pivot = Mat4x4f32.translate(Vec3f32{ cp.x, cp.y, 0.0 });
    const translation = Mat4x4f32.translate(t);
    const rotation = Mat4x4f32.rotateZ(r);
    const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
    return translation.mul(rotation.mul(scale.mul(pivot)));
}

// ──────────────────────────────────────────────────────────────────────
//  srt2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn srt2dMatrix(t: Vec3f32, s: Vec2f32, r: f32) Mat4x4f32 {
    const translation = Mat4x4f32.translate(t);
    const rotation = Mat4x4f32.rotateZ(r);
    const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
    return translation.mul(rotation.mul(scale));
}

// ──────────────────────────────────────────────────────────────────────
//  st2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn st2dMatrix(t: Vec3f32, s: Vec2f32) Mat4x4f32 {
    const translation = Mat4x4f32.translate(t);
    const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
    return translation.mul(scale);
}

// ──────────────────────────────────────────────────────────────────────
//  rt2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn rt2dMatrix(t: Vec3f32, r: f32) Mat4x4f32 {
    const translation = Mat4x4f32.translate(t);
    const rotation = Mat4x4f32.rotateZ(r);
    return translation.mul(rotation);
}

// ──────────────────────────────────────────────────────────────────────
//  t2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn t2dMatrix(t: Vec3f32) Mat4x4f32 {
    return Mat4x4f32.translate(t);
}

// ──────────────────────────────────────────────────────────────────────
//  src2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn src2dMatrix(s: Vec2f32, r: f32, cp: Vec2f32) Mat4x4f32 {
    const pivot = Mat4x4f32.translate(Vec3f32{ cp.x, cp.y, 0.0 });
    const rotation = Mat4x4f32.rotateZ(r);
    const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
    return rotation.mul(scale.mul(pivot));
}

// ──────────────────────────────────────────────────────────────────────
//  sr2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn sr2dMatrix(s: Vec2f32, r: f32) Mat4x4f32 {
    const rotation = Mat4x4f32.rotateZ(r);
    const scale = Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
    return rotation.mul(scale);
}

// ──────────────────────────────────────────────────────────────────────
//  s2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn s2dMatrix(s: Vec2f32) Mat4x4f32 {
    return Mat4x4f32.scale(Vec3f32{ s.x, s.y, 1.0 });
}

// ──────────────────────────────────────────────────────────────────────
//  r2dMatrix
// ──────────────────────────────────────────────────────────────────────

pub fn r2dMatrix(r: f32) Mat4x4f32 {
    return Mat4x4f32.rotateZ(r);
}

// ──────────────────────────────────────────────────────────────────────
//  srt2dMatrix2 — optimized dispatch
// ──────────────────────────────────────────────────────────────────────

pub fn srt2dMatrix2(t: Vec3f32, s: Vec2f32, r: f32, cp: Vec2f32) Mat4x4f32 {
    if (cp.x != 0.0 or cp.y != 0.0) {
        return srtc2dMatrix(t, s, r, cp);
    }
    if (r != 0.0) {
        if (s.x != 1.0 or s.y != 1.0) {
            return srt2dMatrix(t, s, r);
        } else {
            return rt2dMatrix(t, r);
        }
    }
    if (s.x != 1.0 or s.y != 1.0) {
        return st2dMatrix(t, s);
    }
    return t2dMatrix(t);
}

// ──────────────────────────────────────────────────────────────────────
//  sr2dMatrix2 — optimized dispatch, returns ?Mat4x4f32
// ──────────────────────────────────────────────────────────────────────

pub fn sr2dMatrix2(s: Vec2f32, r: f32, cp: Vec2f32) ?Mat4x4f32 {
    if (cp.x != 0.0 or cp.y != 0.0) {
        return src2dMatrix(s, r, cp);
    }
    if (r != 0.0) {
        if (s.x != 1.0 or s.y != 1.0) {
            return sr2dMatrix(s, r);
        } else {
            return r2dMatrix(r);
        }
    }
    if (s.x != 1.0 or s.y != 1.0) {
        return s2dMatrix(s);
    }
    return null;
}
