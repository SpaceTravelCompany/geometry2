//! geometry2.linalg.triangulation — Odin shared/geometry/triangulation 1:1 포팅.
//! libtess2 (memononen/libtess2) C 라이브러리의 얇은 Zig 래퍼.
//!
//! 외부 C 함수 선언 (c-abi 직접 선언, @cImport 최소화 정책).
//! 빌드 시 deps/libtess2/ 의 C 소스를 컴파일하여 링크한다.

const std = @import("std");

// ══════════════════════════════════════════════════════════════════════════════
// libtess2 C API 직접 선언
// ══════════════════════════════════════════════════════════════════════════════

/// libtess2의 불투명 테셀레이터 구조체.
const Tessellator = opaque {};

/// 테셀레이션 결과 상태 코드 (tesselator.h TESSstatus enum).
/// 주의: C 매크로 이름은 `TESS_STATUS_*`이지만, Zig 식별자 컨벤션
/// (PascalCase) + 의미상 단순화를 위해 `Status` 접두사만 사용한다.
pub const StatusOk: c_int = 0;
pub const StatusOutOfMemory: c_int = 1;
pub const StatusInvalidInput: c_int = 2;

/// 감지되지 않은 요소/정점을 표시하는 센티널 값 (−1).
/// C 매크로 `TessUndef` (`#define TessUndef (~(TESSindex)0)`) 와 값 동일.
pub const TessUndef: c_int = -1;

/// 와인딩 규칙 (WindingRule enum과 값 동일).
/// C 매크로 `TESS_WINDING_*` 와 값 동일.
pub const TessWindingOdd: c_int = 0;
pub const TessWindingNonZero: c_int = 1;
pub const TessWindingPositive: c_int = 2;
pub const TessWindingNegative: c_int = 3;
pub const TessWindingAbsGeqTwo: c_int = 4;

/// 요소 유형 (ElementType enum과 값 동일).
/// C 매크로 `TESS_POLYGONS` 등 와 값 동일.
pub const TessPolygons: c_int = 0;
pub const TessConnectedPolygons: c_int = 1;
pub const TessBoundaryContours: c_int = 2;

/// 와인딩 규칙 enum (tesselator.h TessWindingRule).
pub const WindingRule = enum(c_int) {
    ODD = 0,
    NONZERO = 1,
    POSITIVE = 2,
    NEGATIVE = 3,
    ABS_GEQ_TWO = 4,
};

/// 요소 유형 enum (tesselator.h TessElementType).
pub const ElementType = enum(c_int) {
    POLYGONS = 0,
    CONNECTED_POLYGONS = 1,
    BOUNDARY_CONTOURS = 2,
};

/// libtess2 C API: 테셀레이터 생성 (alloc이 null이면 기본 malloc/free 사용).
extern "c" fn tessNewTess(alloc: ?*anyopaque) ?*Tessellator;

/// libtess2 C API: 테셀레이터 소멸.
extern "c" fn tessDeleteTess(tess: ?*Tessellator) void;

/// libtess2 C API: 외곽선(contour) 추가.
/// pointer는 [size]float 정점 배열, stride는 연속 정점 간 바이트 오프셋.
extern "c" fn tessAddContour(tess: ?*Tessellator, size: c_int, pointer: *const anyopaque, stride: c_int, count: c_int) void;

/// libtess2 C API: 테셀레이션 실행.
/// 성공 시 1, 실패 시 0 반환.
extern "c" fn tessTesselate(tess: ?*Tessellator, winding_rule: c_int, element_type: c_int, poly_size: c_int, vertex_size: c_int, normal: ?*const f32) c_int;

/// libtess2 C API: 결과 정점 배열 포인터 반환.
extern "c" fn tessGetVertices(tess: ?*Tessellator) [*]const f32;

/// libtess2 C API: 결과 정점 개수 반환.
extern "c" fn tessGetVertexCount(tess: ?*Tessellator) c_int;

/// libtess2 C API: 정점 인덱스 맵 반환 (테셀레이터 정점 → 원본 외곽선 정점).
extern "c" fn tessGetVertexIndices(tess: ?*Tessellator) [*]const c_int;

/// libtess2 C API: 결과 요소 배열 포인터 반환.
extern "c" fn tessGetElements(tess: ?*Tessellator) [*]const c_int;

/// libtess2 C API: 결과 요소 개수 반환.
extern "c" fn tessGetElementCount(tess: ?*Tessellator) c_int;

// ══════════════════════════════════════════════════════════════════════════════
// Error type
// ══════════════════════════════════════════════════════════════════════════════

/// Odin `TrianguateError :: union #shared_nil { __TrianguateError, runtime.Allocator_Error }` 1:1 대응.
/// `__TrianguateError` = `error { FAILED, TOO_FEW_POINTS }`,
/// `runtime.Allocator_Error` = `std.mem.Allocator.Error`.
pub const TrianguateError = __TrianguateError || std.mem.Allocator.Error;

pub const __TrianguateError = error{
    Failed,
    TooFewPoints,
};

// ══════════════════════════════════════════════════════════════════════════════
// Convenience wrapper (Odin libtess2.odin `triangulate` 1:1)
// ══════════════════════════════════════════════════════════════════════════════

/// 2D 폴리곤 외곽선 세트를 삼각분할한다.
/// 각 poly는 [2]f32 정점 배열 (CCW 권장).
/// offset: 출력 인덱스에 더할 값 (인덱스 버퍼 병합용).
/// allocator: 메모리 할당자.
/// 반환: 삼각형 정점 인덱스 배열 (3개씩 그룹), 실패 시 오류.
fn triangulate(
    comptime Pt: type,
    polys: []const []const Pt,
    offset: u32,
    allocator: std.mem.Allocator,
) (std.mem.Allocator.Error || error{Failed})![]u32 {
    // 1. 테셀레이터 생성
    const tess = tessNewTess(null) orelse return error.Failed;
    defer tessDeleteTess(tess);

    // 2. 각 외곽선 추가 (3점 미만 스킵 — Odin과 동일)
    for (polys) |poly| {
        if (poly.len < 3) continue;
        tessAddContour(
            tess,
            2, // vertex size = 2 (2D)
            @ptrCast(poly.ptr),
            @sizeOf(Pt), // stride = 8 bytes (Pt 는 [2]f32 와 동일 레이아웃)
            @intCast(poly.len),
        );
    }

    // 3. 테셀레이션 실행 (삼각형, ODD 와인딩)
    const result = tessTesselate(tess, @intFromEnum(WindingRule.ODD), @intFromEnum(ElementType.POLYGONS), 3, 2, null);
    if (result == 0) return error.Failed;

    // 4. 결과 개수 확인
    const vert_count = @as(usize, @intCast(tessGetVertexCount(tess)));
    const vert_indices = tessGetVertexIndices(tess);
    const elem_count = @as(usize, @intCast(tessGetElementCount(tess)));
    const elements = tessGetElements(tess);

    if (elem_count == 0 or vert_count == 0) return error.Failed;

    // 5. 유효한 삼각형 개수 계산 (TessUndef가 아닌 요소)
    var tri_count: usize = 0;
    {
        var i: usize = 0;
        while (i < elem_count) : (i += 1) {
            const base = i * 3;
            if (elements[base] != TessUndef and
                elements[base + 1] != TessUndef and
                elements[base + 2] != TessUndef)
            {
                tri_count += 1;
            }
        }
    }
    if (tri_count == 0) return error.Failed;

    // 6. 결과 버퍼 할당
    var indices = try allocator.alloc(u32, tri_count * 3);

    // 7. 인덱스 변환: elements → vertexIndices → 원본 인덱스 → offset 적용
    var idx: usize = 0;
    {
        var i: usize = 0;
        while (i < elem_count) : (i += 1) {
            const base = i * 3;
            if (elements[base] == TessUndef or
                elements[base + 1] == TessUndef or
                elements[base + 2] == TessUndef) continue;

            const v0 = vert_indices[@as(usize, @intCast(elements[base]))];
            const v1 = vert_indices[@as(usize, @intCast(elements[base + 1]))];
            const v2 = vert_indices[@as(usize, @intCast(elements[base + 2]))];

            // 교차점에서 생성된 정점(TessUndef) 스킵
            if (v0 == TessUndef or v1 == TessUndef or v2 == TessUndef) continue;

            indices[idx + 0] = @as(u32, @intCast(v0)) + offset;
            indices[idx + 1] = @as(u32, @intCast(v1)) + offset;
            indices[idx + 2] = @as(u32, @intCast(v2)) + offset;
            idx += 3;
        }
    }

    // 8. 결과 슬라이스 정리
    if (idx == 0) {
        allocator.free(indices);
        return error.Failed;
    }

    if (idx < tri_count * 3) {
        indices = try allocator.realloc(indices, idx);
    }

    return indices;
}

// ══════════════════════════════════════════════════════════════════════════════
// Public API (Odin TrianguatePolygons 1:1)
// ══════════════════════════════════════════════════════════════════════════════

/// 2D 폴리곤 외곽선 세트를 삼각분할하여 인덱스 버퍼를 반환한다.
///
///   poly: 각 외곽선은 `Pt` 정점의 슬라이스. `Pt` 는
///     메모리 레이아웃이 `[2]f32` 와 동일한 2D 점 타입
///     (예: `[2]f32`, `Vec2(f32)`, `linalg.Vector2f32`).
///   allocator: 메모리 할당자.
///   offset: 출력 인덱스에 더할 값 (인덱스 버퍼 병합용, 기본 0).
///
/// 반환값:
///   성공 시 []u32 (3개씩 삼각형 인덱스 그룹).
///   실패 시 TrianguateError (Failed, TooFewPoints, 또는 Allocator.Error).
pub fn trianguatePolygons(
    comptime Pt: type,
    poly: []const []const Pt,
    allocator: std.mem.Allocator,
    offset: u32,
) TrianguateError![]u32 {
    const out = try triangulate(Pt, poly, offset, allocator);
    // Odin: `if len(outIndices) < 3 do return nil, .FAILED`
    if (out.len < 3) {
        allocator.free(out);
        return error.Failed;
    }
    return out;
}

// ══════════════════════════════════════════════════════════════════════════════
// Tests (Odin triangulation_test.odin 1:1)
// ══════════════════════════════════════════════════════════════════════════════

test "triangulationSquare" {
    const allocator = std.testing.allocator;

    // Odin `_makeSquare(0, 0, 10)`:
    //   half = 5
    //   {-5, -5}, {5, -5}, {5, 5}, {-5, 5}
    const square = [_][2]f32{
        .{ -5, -5 },
        .{ 5, -5 },
        .{ 5, 5 },
        .{ -5, 5 },
    };
    const poly = [_][]const [2]f32{&square};

    const indices = try trianguatePolygons([2]f32, &poly, allocator, 0);
    defer allocator.free(indices);

    // square → 2 triangles = 6 indices
    try std.testing.expectEqual(@as(usize, 6), indices.len);
}

test "triangulationTwoSquares" {
    const allocator = std.testing.allocator;

    // Odin `_makeSquare(0, 0, 10)`와 동일
    const sq1 = [_][2]f32{
        .{ -5, -5 },
        .{ 5, -5 },
        .{ 5, 5 },
        .{ -5, 5 },
    };
    // Odin `_makeSquare(100, 0, 10)`
    const sq2 = [_][2]f32{
        .{ 100 - 5, 0 - 5 },
        .{ 100 + 5, 0 - 5 },
        .{ 100 + 5, 0 + 5 },
        .{ 100 - 5, 0 + 5 },
    };
    const poly = [_][]const [2]f32{ &sq1, &sq2 };

    const indices = try trianguatePolygons([2]f32, &poly, allocator, 0);
    defer allocator.free(indices);

    // 2 squares → 4 triangles = 12 indices
    try std.testing.expectEqual(@as(usize, 12), indices.len);
}

test "triangulationTriangle" {
    const allocator = std.testing.allocator;

    const tri = [_][2]f32{
        .{ 0, 0 },
        .{ 10, 0 },
        .{ 5, 10 },
    };
    const poly = [_][]const [2]f32{&tri};

    const indices = try trianguatePolygons([2]f32, &poly, allocator, 0);
    defer allocator.free(indices);

    // triangle → 1 triangle = 3 indices
    try std.testing.expectEqual(@as(usize, 3), indices.len);
    // 모든 인덱스가 유효 범위 내
    for (indices) |idx| {
        try std.testing.expect(idx < 3);
    }
}
