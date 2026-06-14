const std = @import("std");

// ──── Error Set ─────────────────────────────────────────────────────────────
/// Clipper-specific errors. `OutOfMemory` added for allocator failures.
pub const ClipperError = error{
    Failed,
    TooSmall,
    LengthMismatch,
    OutOfMemory,
};

// ──── Public Enums ──────────────────────────────────────────────────────────
/// Windowing rule for polygon fills.
pub const FillRule = enum(u8) {
    EvenOdd,
    NonZero,
    Positive,
    Negative,
};

/// Boolean operation type.
pub const ClipType = enum(u8) {
    NoClip,
    Intersection,
    Union,
    Difference,
    Xor,
};

/// Join style for offsetting.
pub const JoinType = enum(u8) {
    Square,
    Bevel,
    Round,
    Miter,
};

/// End cap style for offsetting.
pub const EndType = enum(u8) {
    Polygon,
    Joined,
    Butt,
    Square,
    Round,
};

// ──── Private Enums ─────────────────────────────────────────────────────────
/// Path type in the active edge lists.
const PathType = enum(u8) {
    Subject,
    Clip,
};

/// Vertex flags for marking special vertices.
const VertexFlags = enum(u32) {
    Empty = 0,
    OpenStart = 1,
    OpenEnd = 2,
    LocalMax = 4,
    LocalMin = 8,
};

/// Which side a join connects to.
const JoinWith = enum(u8) {
    NoJoin,
    Left,
    Right,
};

/// Edge location during clipping.
const Location = enum(u8) {
    Left = 0,
    Top = 1,
    Right = 2,
    Bottom = 3,
    Inside = 4,
};

/// Result of point-in-polygon test.
const PointInPolygonResult = enum(u8) {
    IsOn,
    IsInside,
    IsOutside,
};

// ──── Constants ─────────────────────────────────────────────────────────────
const Eps: f64 = 1e-9;
const SideEps: f64 = 1e-7;
const ArcConst: f64 = 0.002;

// ──── Internal Point (2D only) ───────────────────────────────────────────────
/// Internal 2D point representation. Z-coordinate is omitted for Stage 1.
pub const Point = struct {
    x: f64,
    y: f64,
};

// ──── Internal Types ────────────────────────────────────────────────────────
/// Doubly-linked vertex in the scanbeam grid.
const Vertex = struct {
    pt: Point,
    next: ?*Vertex,
    prev: ?*Vertex,
    flags: VertexFlags,
};

/// Local minimum record.
const LocalMinima = struct {
    vertex: ?*Vertex,
    polytype: PathType,
    is_open: bool,
};

/// Output polygon point (doubly-linked).
const OutPt = struct {
    pt: Point,
    next: ?*OutPt,
    prev: ?*OutPt,
    outrec: ?*OutRec,
    horz: ?*HorzSegment,
};

/// Output polygon record.
const OutRec = struct {
    idx: usize,
    owner: ?*OutRec,
    front_edge: ?*Active,
    back_edge: ?*Active,
    pts: ?*OutPt,
    bounds: RectF64,
    path: std.ArrayList(Point),
    is_open: bool,
};

/// Active edge in the AEL/SEL.
const Active = struct {
    bot: Point,
    top: Point,
    curr_x: f64,
    dx: f64,
    wind_dx: i32,
    wind_cnt: i32,
    wind_cnt2: i32,
    outrec: ?*OutRec,
    prev_in_ael: ?*Active,
    next_in_ael: ?*Active,
    prev_in_sel: ?*Active,
    next_in_sel: ?*Active,
    jump: ?*Active,
    vertex_top: ?*Vertex,
    local_min: ?*LocalMinima,
    is_left_bound: bool,
    join_with: JoinWith,
};

/// Intersection node for edge crossings.
const IntersectNode = struct {
    pt: Point,
    edge1: ?*Active,
    edge2: ?*Active,
};

/// Horizontal segment record.
const HorzSegment = struct {
    left_op: ?*OutPt,
    right_op: ?*OutPt,
    left_to_right: bool,
};

/// Horizontal join record.
const HorzJoin = struct {
    op1: ?*OutPt,
    op2: ?*OutPt,
};

/// Axis-aligned rectangle (f64).
pub const RectF64 = struct {
    left: f64,
    top: f64,
    right: f64,
    bottom: f64,
};

/// Group for offset engine (paths before offsetting).
const Group = struct {
    paths_in: std.ArrayList([]Point),
    lowest_path_idx: i32,
    is_reversed: bool,
    join_type: JoinType,
    end_type: EndType,
};

/// Offset engine (Minkowski sum of polygons).
pub const ClipperOffset = struct {
    delta: f64 = 0,
    group_delta: f64 = 0,
    temp_lim: f64 = 0,
    steps_per_rad: f64 = 0,
    step_sin: f64 = 0,
    step_cos: f64 = 0,
    norms: std.ArrayList(Point),
    path_out: std.ArrayList(Point),
    solution: ?*std.ArrayList([]Point) = null,
    groups: std.ArrayList(Group),
    join_type: JoinType = .Square,
    end_type: EndType = .Polygon,
    miter_limit: f64 = 2.0,
    arc_tolerance: f64 = 0,
    preserve_collinear: bool = false,
    reverse_solution: bool = false,
    error_code: i32 = 0,
};

/// Base boolean operations engine.
pub const ClipperBase = struct {
    cliptype: ClipType = .NoClip,
    fillrule: FillRule = .NonZero,
    fillpos: FillRule = .Positive,
    bot_y: f64 = 0,
    minima_list_sorted: bool = false,
    using_polytree: bool = false,
    actives: ?*Active = null,
    sel: ?*Active = null,
    minima_list: std.ArrayList(?*LocalMinima),
    current_locmin_iter: usize = 0,
    vertex_lists: std.ArrayList(?*Vertex),
    scanline_list: std.ArrayList(f64),
    intersect_nodes: std.ArrayList(IntersectNode),
    horz_seg_list: std.ArrayList(HorzSegment),
    horz_join_list: std.ArrayList(HorzJoin),
    outrec_list: std.ArrayList(?*OutRec),
    preserve_collinear: bool = true,
    reverse_solution: bool = false,
    error_code: i32 = 0,
    has_open_paths: bool = false,
    succeeded: bool = true,
};

/// Light-weight point for rectangular clipping output.
const OutPt2 = struct {
    pt: Point,
    owner_idx: usize,
    edge: ?*std.ArrayList(?*OutPt2),
    next: ?*OutPt2,
    prev: ?*OutPt2,
};

/// Rectangular clipping engine (2D only).
pub const RectClip64 = struct {
    rect: RectF64 = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    rect_as_path: [4]Point = undefined,
    rect_mp: Point = .{ .x = 0, .y = 0 },
    path_bounds: RectF64 = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    op_container: std.ArrayList(OutPt2),
    results: std.ArrayList(?*OutPt2),
    edges: [8]std.ArrayList(?*OutPt2),
    start_locs: std.ArrayList(Location),
};

/// RectClipLines64 wraps RectClip64 for line clipping.
const RectClipLines64 = struct {
    base: RectClip64 = .{},
};

// ──── Point Math Helpers (2D) ───────────────────────────────────────────────
/// Add two points.
fn ptAdd(a: Point, b: Point) Point {
    return .{ .x = a.x + b.x, .y = a.y + b.y };
}

/// Subtract b from a.
fn ptSub(a: Point, b: Point) Point {
    return .{ .x = a.x - b.x, .y = a.y - b.y };
}

/// Multiply point by scalar.
fn ptMul(a: Point, s: f64) Point {
    return .{ .x = a.x * s, .y = a.y * s };
}

/// 2D cross product (a × b = a.x*b.y - a.y*b.x).
fn cross(a: Point, b: Point) f64 {
    return a.x * b.y - a.y * b.x;
}

/// 2D dot product.
fn dot(a: Point, b: Point) f64 {
    return a.x * b.x + a.y * b.y;
}

/// Squared length of point vector.
fn lenSq(a: Point) f64 {
    return a.x * a.x + a.y * a.y;
}

/// Cross product of vectors (b-a) and (c-b).
fn crossProduct(a: Point, b: Point, c: Point) f64 {
    return (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
}

/// Dot product of vectors (b-a) and (c-b).
fn dotProduct(a: Point, b: Point, c: Point) f64 {
    return (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y);
}

/// Squared distance between two points.
fn distanceSqr(a: Point, b: Point) f64 {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return dx * dx + dy * dy;
}

/// Signed area of polygon path (positive = CCW).
fn areaPath(path: []const Point) f64 {
    if (path.len < 3) return 0;
    var area: f64 = 0;
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        const j = if (i + 1 < path.len) i + 1 else 0;
        area += path[i].x * path[j].y - path[j].x * path[i].y;
    }
    return area * 0.5;
}

/// Reverse path in place.
fn reversePath(path: []Point) void {
    var i: usize = 0;
    while (i < path.len / 2) : (i += 1) {
        const j = path.len - 1 - i;
        const tmp = path[i];
        path[i] = path[j];
        path[j] = tmp;
    }
}

/// Signed area from OutPt linked list.
fn areaOutPt(op: ?*OutPt) f64 {
    if (op == null) return 0;
    var result: f64 = 0;
    var op2 = op;
    while (true) {
        const cur = op2.?;
        const prev = cur.prev orelse break;
        result += (prev.pt.y + cur.pt.y) * (prev.pt.x - cur.pt.x);
        op2 = cur.next;
        if (op2 == op) break;
    }
    return result * 0.5;
}

/// Signed area of triangle abc.
fn areaTriangle(a: Point, b: Point, c: Point) f64 {
    return (c.y + a.y) * (c.x - a.x) + (a.y + b.y) * (a.x - b.x) + (b.y + c.y) * (b.x - c.x);
}

// ============================================================================
// Stage 2: Geometry Predicates + Edge Helpers + ClipperBase Engine
// Odin clipper.odin lines 480~1012 포팅
// ============================================================================

// ──── Geometry Predicates (기하학 술어) ───────────────────────────────────────
// 모든 함수는 Point 타입에 대해 동작. Odin #force_inline proc "contextless" → Zig inline fn

/// 두 점 사이의 기울기. 수평이면 ±F64_MAX 반환.
inline fn getDx(pt1: Point, pt2: Point) f64 {
    const dy = pt2.y - pt1.y;
    if (@abs(dy) > Eps) {
        return (pt2.x - pt1.x) / dy;
    } else if (pt2.x > pt1.x) {
        return -std.math.f64_max;
    } else {
        return std.math.f64_max;
    }
}

/// 주어진 Y에서의 X 좌표 계산.
inline fn topX(dx: f64, bot: Point, top: Point, currentY: f64) f64 {
    if (currentY == top.y or top.x == bot.x) {
        return top.x;
    } else if (currentY == bot.y) {
        return bot.x;
    } else {
        return bot.x + dx * (currentY - bot.y);
    }
}

/// 엣지가 수평인지 검사.
inline fn isHorizontalE(e: ?*Active) bool {
    return @abs(e.?.top.y - e.?.bot.y) < Eps;
}

/// 두 점이 같은 Y인지 검사.
inline fn isHorizontalPt(p1: Point, p2: Point) bool {
    return @abs(p1.y - p2.y) < Eps;
}

/// 수평 엣지가 오른쪽으로 향하는지.
inline fn isHeadingRightHorz(e: ?*Active) bool {
    return e.?.dx == -std.math.f64_max;
}

/// 수평 엣지가 왼쪽으로 향하는지.
inline fn isHeadingLeftHorz(e: ?*Active) bool {
    return e.?.dx == std.math.f64_max;
}

/// 엣지의 dx 설정.
inline fn setDx(e: ?*Active) void {
    e.?.dx = getDx(e.?.bot, e.?.top);
}

/// 엣지의 다음 꼭짓점 반환.
inline fn nextVertex(e: ?*Active) ?*Vertex {
    if (e.?.wind_dx > 0) {
        return e.?.vertex_top.?.next;
    } else {
        return e.?.vertex_top.?.prev;
    }
}

/// 엣지의 이전 이전 꼭짓점 반환.
inline fn prevPrevVertex(e: ?*Active) ?*Vertex {
    if (e.?.wind_dx > 0) {
        return e.?.vertex_top.?.prev.?.prev;
    } else {
        return e.?.vertex_top.?.next.?.next;
    }
}

/// 세 점이 공선인지 검사.
inline fn isCollinear(a: Point, sharedPt: Point, b: Point) bool {
    return @abs(crossProduct(a, sharedPt, b)) < Eps;
}

/// 외적 부호 (-1, 0, 1) 반환.
inline fn crossProductSign(a: Point, b: Point, c: Point) i32 {
    const cp = crossProduct(a, b, c);
    if (cp > Eps) return 1;
    if (cp < -Eps) return -1;
    return 0;
}

/// 두 선분의 교차점 계산. ip에 결과 저장, 성공 시 true.
fn getLineIntersectPt(ln1a: Point, ln1b: Point, ln2a: Point, ln2b: Point, ip: *Point) bool {
    const dx1 = ln1b.x - ln1a.x;
    const dy1 = ln1b.y - ln1a.y;
    const dx2 = ln2b.x - ln2a.x;
    const dy2 = ln2b.y - ln2a.y;

    const det = dy1 * dx2 - dy2 * dx1;
    if (@abs(det) < Eps) return false;

    const t = ((ln1a.x - ln2a.x) * dy2 - (ln1a.y - ln2a.y) * dx2) / det;
    if (t <= 0.0) {
        ip.* = ln1a;
    } else if (t >= 1.0) {
        ip.* = ln1b;
    } else {
        ip.x = ln1a.x + t * dx1;
        ip.y = ln1a.y + t * dy1;
    }
    return true;
}

/// 두 선분이 교차하는지 검사. inclusive: 경계 포함 여부.
fn segmentsIntersect(seg1a: Point, seg1b: Point, seg2a: Point, seg2b: Point, inclusive: bool) bool {
    const dy1 = seg1b.y - seg1a.y;
    const dx1 = seg1b.x - seg1a.x;
    const dy2 = seg2b.y - seg2a.y;
    const dx2 = seg2b.x - seg2a.x;
    const cp = dy1 * dx2 - dy2 * dx1;
    if (@abs(cp) < Eps) return false;

    var t = (seg1a.x - seg2a.x) * dy2 - (seg1a.y - seg2a.y) * dx2;
    if (inclusive) {
        if (@abs(t) < Eps) return true;
        if (t > 0) {
            if (cp < 0 or t > cp) return false;
        } else if (cp > 0 or t < cp) return false;
    } else {
        if (@abs(t) < Eps) return false;
        if (t > 0) {
            if (cp < 0 or t >= cp) return false;
        } else if (cp > 0 or t <= cp) return false;
    }

    t = (seg1a.x - seg2a.x) * dy1 - (seg1a.y - seg2a.y) * dx1;
    if (inclusive) {
        if (@abs(t) < Eps) return true;
        if (t > 0) {
            return cp > 0 and t <= cp;
        } else {
            return cp < 0 and t >= cp;
        }
    } else {
        if (@abs(t) < Eps) return false;
        if (t > 0) {
            return cp > 0 and t < cp;
        } else {
            return cp < 0 and t > cp;
        }
    }
}

/// 점에서 직선까지의 수직 거리 제곱.
fn perpendicDistFromLineSqrd(pt: Point, line1: Point, line2: Point) f64 {
    const a = pt.x - line1.x;
    const b = pt.y - line1.y;
    const c = line2.x - line1.x;
    const d = line2.y - line1.y;
    if (c == 0 and d == 0) return 0;
    return (a * d - c * b) * (a * d - c * b) / (c * c + d * d);
}

/// 점 이동.
inline fn translatePoint(pt: Point, dx: f64, dy: f64) Point {
    return .{ .x = pt.x + dx, .y = pt.y + dy };
}

/// 점 반사.
inline fn reflectPoint(pt: Point, pivot: Point) Point {
    return .{ .x = pivot.x + (pivot.x - pt.x), .y = pivot.y + (pivot.y - pt.y) };
}

/// 선분 위의 가장 가까운 점 반환.
fn getClosestPointOnSegment(offPt: Point, seg1: Point, seg2: Point) Point {
    if (seg1.x == seg2.x and seg1.y == seg2.y) return seg1;
    const dx = seg2.x - seg1.x;
    const dy = seg2.y - seg1.y;
    var q = ((offPt.x - seg1.x) * dx + (offPt.y - seg1.y) * dy) / (dx * dx + dy * dy);
    if (q < 0) q = 0;
    if (q > 1) q = 1;
    return .{ .x = seg1.x + q * dx, .y = seg1.y + q * dy };
}

/// 두 점이 거의 같은지 검사 (SideEps 이내).
inline fn pointsReallyClose(a: Point, b: Point) bool {
    return @abs(a.x - b.x) < SideEps and @abs(a.y - b.y) < SideEps;
}

// ──── Vertex Flag Helpers (Vertex 플래그 헬퍼) ───────────────────────────────────

/// Vertex 플래그 확인.
inline fn hasFlag(v: ?*Vertex, f: VertexFlags) bool {
    return (@as(u32, @bitCast(v.?.flags)) & @as(u32, @bitCast(f))) != 0;
}

/// Vertex 플래그 설정.
inline fn setFlag(v: *Vertex, f: VertexFlags) void {
    v.flags = @bitCast(@as(u32, @bitCast(v.flags)) | @as(u32, @bitCast(f)));
}

// ──── Active Edge Helpers (Active 엣지 헬퍼) ─────────────────────────────────────

/// 폴리곤 타입 반환.
inline fn getPolyType(e: ?*Active) PathType {
    return e.?.local_min.?.polytype;
}

/// 같은 폴리곤 타입인지 검사.
inline fn isSamePolyType(e1: ?*Active, e2: ?*Active) bool {
    return e1.?.local_min.?.polytype == e2.?.local_min.?.polytype;
}

/// 홀수인지 검사.
inline fn isOdd(val: anytype) bool {
    return (val & 1) != 0;
}

/// 핫 엣지인지 (outrec != null).
inline fn isHotEdge(e: ?*Active) bool {
    return e.?.outrec != null;
}

/// 열린 경로인지.
inline fn isOpen(e: ?*Active) bool {
    return e.?.local_min.?.is_open;
}

/// 열린 경로의 끝인지.
inline fn isOpenEnd(v: ?*Vertex) bool {
    return hasFlag(v.?, .OpenStart) or hasFlag(v.?, .OpenEnd);
}

/// 엣지의 꼭짓점이 열린 끝인지.
inline fn isOpenEndE(e: ?*Active) bool {
    return isOpenEnd(e.?.vertex_top);
}

/// 이전 핫 엣지 찾기.
fn getPrevHotEdge(e: ?*Active) ?*Active {
    var prev = e.?.prev_in_ael;
    while (prev != null and (isOpen(prev) or !isHotEdge(prev))) {
        prev = prev.?.prev_in_ael;
    }
    return prev;
}

/// 앞면 엣지인지.
inline fn isFront(e: ?*Active) bool {
    return e == e.?.outrec.?.front_edge;
}

/// 유효하지 않은 경로인지.
inline fn isInvalidPath(op: ?*OutPt) bool {
    return op == null or op.?.next == op;
}

/// 최대점 꼭짓점인지.
inline fn isMaximaV(v: ?*Vertex) bool {
    return hasFlag(v.?, .LocalMax);
}

/// 최대점 엣지인지.
inline fn isMaximaE(e: ?*Active) bool {
    return isMaximaV(e.?.vertex_top);
}

/// 조인된 엣지인지.
inline fn isJoined(e: ?*Active) bool {
    return e.?.join_with != .NoJoin;
}

/// 출력 점 개수.
fn pointCount(op: ?*OutPt) usize {
    if (op == null) return 0;
    var op2 = op;
    var cnt: usize = 0;
    while (true) {
        op2 = op2.?.next;
        cnt += 1;
        if (op2 == op) break;
    }
    return cnt;
}

/// 유효한 닫힌 경로인지.
fn isValidClosedPath(op: ?*OutPt) bool {
    if (op == null) return false;
    if (op.?.next == op) return false;
    if (op.?.next == op.?.prev) return false;
    return !isVerySmallTriangle(op);
}

/// 매우 작은 삼각형인지.
fn isVerySmallTriangle(op: ?*OutPt) bool {
    if (op.?.next.?.next != op.?.prev) return false;
    const prev_pt = op.?.prev.?.pt;
    const next_pt = op.?.next.?.pt;
    const pt = op.?.pt;
    return pointsReallyClose(prev_pt, next_pt) or pointsReallyClose(pt, next_pt) or pointsReallyClose(pt, prev_pt);
}

// ──── ClipperBase Engine Methods (ClipperBase 엔진 메서드) ───────────────────────

/// 로컬 최소값 꼭짓점 추가 (중복 방지).
fn addLocMin(
    locMinList: *std.ArrayList(?*LocalMinima),
    vert: *Vertex,
    polytype: PathType,
    is_open: bool,
    allocator: std.mem.Allocator,
) void {
    if (hasFlag(vert, .LocalMin)) return;
    setFlag(vert, .LocalMin);

    const lm = allocator.create(LocalMinima) catch return;
    lm.* = .{
        .vertex = vert,
        .polytype = polytype,
        .is_open = is_open,
    };
    locMinList.append(allocator, lm) catch {};
}

/// 입력 경로를 내부 Vertex 연결 리스트 + 로컬 최소값으로 변환.
fn addPaths(
    paths: []const []const Point,
    polytype: PathType,
    is_open: bool,
    vertexLists: *std.ArrayList(?*Vertex),
    locMinList: *std.ArrayList(?*LocalMinima),
    allocator: std.mem.Allocator,
) void {
    // 총 정점 수 계산
    var total_vertex_count: usize = 0;
    for (paths) |path| {
        total_vertex_count += path.len;
    }
    if (total_vertex_count == 0) return;

    // 모든 정점을 하나의 contiguous 블록으로 할당 (temp allocator)
    const allVertices = allocator.alloc(Vertex, total_vertex_count) catch return;
    defer allocator.free(allVertices);

    var vi: usize = 0; // allVertices 인덱스

    for (paths) |path| {
        if (path.len == 0) continue;

        const v0_idx = vi;
        const v0 = &allVertices[v0_idx];

        var curr_v = v0;
        var prev_v: ?*Vertex = null;
        curr_v.prev = null;
        var cnt: usize = 0;

        var pt_idx: usize = 0;
        while (pt_idx < path.len) : (pt_idx += 1) {
            const pt = path[pt_idx];
            if (prev_v != null) {
                // 중복 연속 점 제거
                if (prev_v.?.pt.x == pt.x and prev_v.?.pt.y == pt.y) continue;
                prev_v.?.next = curr_v;
            }
            curr_v.prev = prev_v;
            curr_v.pt = pt;
            curr_v.flags = .Empty;
            prev_v = curr_v;
            vi += 1;
            cnt += 1;
            if (vi < total_vertex_count) {
                curr_v = &allVertices[vi];
            }
        }

        // 퇴화 경로 스킵
        if (prev_v == null or prev_v.?.prev == null) continue;

        // 닫힌 경로: 끝 점 중복 제거
        if (!is_open and prev_v.?.pt.x == v0.pt.x and prev_v.?.pt.y == v0.pt.y) {
            prev_v = prev_v.?.prev;
        }

        // 원형 이중 연결 리스트 완성
        prev_v.?.next = v0;
        v0.prev = prev_v;

        if (cnt < 2 or (cnt == 2 and !is_open)) continue;

        // ── 로컬 최소값/최대값 탐색 및 플래그 설정 ──
        var going_up: bool = undefined;
        var going_up0: bool = undefined;

        if (is_open) {
            curr_v = v0.next;
            while (curr_v != v0 and @abs(curr_v.?.pt.y - v0.pt.y) < Eps) {
                curr_v = curr_v.?.next;
            }
            going_up = curr_v.?.pt.y <= v0.pt.y;
            if (going_up) {
                setFlag(v0, .OpenStart);
                _ = addLocMin(locMinList, v0, polytype, true, allocator);
            } else {
                setFlag(v0, .OpenStart);
                setFlag(v0, .LocalMax);
            }
        } else {
            // 닫힌 경로: 초기 방향 결정
            prev_v = v0.prev;
            while (prev_v != v0 and @abs(prev_v.?.pt.y - v0.pt.y) < Eps) {
                prev_v = prev_v.?.prev;
            }
            if (prev_v == v0) continue; // 완전히 평평한 경로 → 스킵
            going_up = prev_v.?.pt.y > v0.pt.y;
        }

        going_up0 = going_up;
        prev_v = v0;
        curr_v = v0.next;
        while (curr_v != v0) {
            if (curr_v.?.pt.y > prev_v.?.pt.y and going_up) {
                setFlag(prev_v.?, .LocalMax);
                going_up = false;
            } else if (curr_v.?.pt.y < prev_v.?.pt.y and !going_up) {
                going_up = true;
                _ = addLocMin(locMinList, prev_v.?, polytype, is_open, allocator);
            }
            prev_v = curr_v;
            curr_v = curr_v.?.next;
        }

        if (is_open) {
            if (going_up) {
                setFlag(prev_v.?, .OpenEnd);
                setFlag(prev_v.?, .LocalMax);
            } else {
                setFlag(prev_v.?, .OpenEnd);
                _ = addLocMin(locMinList, prev_v.?, polytype, is_open, allocator);
            }
        } else if (going_up != going_up0) {
            if (going_up0) {
                _ = addLocMin(locMinList, prev_v.?, polytype, false, allocator);
            } else {
                setFlag(prev_v.?, .LocalMax);
            }
        }
    }

    // vertexLists에 첫 번째 vertex 블록 추가 (단일 블록)
    vertexLists.append(allocator, &allVertices[0]) catch {};
}

/// ClipperBase 초기화.
fn clipperBaseInit(cb: *ClipperBase, allocator: std.mem.Allocator) void {
    _ = allocator;
    cb.* = .{};
    cb.minima_list = std.ArrayList(?*LocalMinima).empty;
    cb.vertex_lists = std.ArrayList(?*Vertex).empty;
    cb.scanline_list = std.ArrayList(f64).empty;
    cb.intersect_nodes = std.ArrayList(IntersectNode).empty;
    cb.horz_seg_list = std.ArrayList(HorzSegment).empty;
    cb.horz_join_list = std.ArrayList(HorzJoin).empty;
    cb.outrec_list = std.ArrayList(?*OutRec).empty;
    cb.preserve_collinear = true;
    cb.fillpos = .Positive;
    cb.succeeded = true;
}

/// ClipperBase 해제.
fn clipperBaseDestroy(cb: *ClipperBase) void {
    cb.* = .{};
}

// ──── Scanline Operations (스캔라인 연산) ───────────────────────────────────────

/// 스캔라인 Y 값 추가.
fn insertScanline(cb: *ClipperBase, y: f64, allocator: std.mem.Allocator) void {
    cb.scanline_list.append(allocator, y) catch {};
}

/// 가장 높은 Y 값 팝 (중복 제거).
fn popScanline(cb: *ClipperBase, y: *f64) bool {
    const sl = cb.scanline_list.items;
    if (sl.len == 0) return false;

    var max_y = sl[0];
    for (sl[1..]) |val| {
        if (val > max_y) max_y = val;
    }

    // max_y 근접값 모두 제거 (중복 제거)
    var j: usize = 0;
    for (sl) |val| {
        if (@abs(val - max_y) > Eps) {
            cb.scanline_list.items[j] = val;
            j += 1;
        }
    }
    cb.scanline_list.shrinkRetainingCapacity(j);
    y.* = max_y;
    return true;
}

/// 주어진 Y의 로컬 최소값 팝.
fn popLocalMinima(cb: *ClipperBase, y: f64, local_minima: **?*LocalMinima) bool {
    if (cb.current_locmin_iter >= cb.minima_list.items.len) return false;
    const lm = cb.minima_list.items[cb.current_locmin_iter];
    if (@abs(lm.?.vertex.?.pt.y - y) > Eps) return false;
    local_minima.* = lm;
    cb.current_locmin_iter += 1;
    return true;
}

/// 스캔라인 정렬 + 초기화.
fn reset(cb: *ClipperBase, allocator: std.mem.Allocator) void {
    if (!cb.minima_list_sorted) {
        // Y 내림차순, X 오름차순 정렬
        std.sort.block(
            LocalMinima,
            cb.minima_list.items,
            {},
            struct {
                fn lessThan(ctx: void, a: ?*LocalMinima, b: ?*LocalMinima) bool {
                    _ = ctx;
                    const a_y = a.?.vertex.?.pt.y;
                    const b_y = b.?.vertex.?.pt.y;
                    if (@abs(b_y - a_y) > Eps) {
                        return b_y < a_y; // Y 내림차순
                    }
                    return b.?.vertex.?.pt.x > a.?.vertex.?.pt.x; // X 오름차순
                }
            }.lessThan,
        );
        cb.minima_list_sorted = true;
    }
    // 모든 최소값 Y를 스캔라인에 추가 (역순)
    var i: usize = cb.minima_list.items.len;
    while (i > 0) {
        i -= 1;
        insertScanline(cb, cb.minima_list.items[i].?.vertex.?.pt.y, allocator);
    }
    cb.current_locmin_iter = 0;
    cb.actives = null;
    cb.sel = null;
    cb.succeeded = true;
}

// ============================================================================
// Stage 3: AEL Operations + Wind Count + Output Construction + Intersection
// Odin clipper.odin lines 1014~2001 포팅
// ============================================================================

// ──── AEL operations ─────────────────────────────────────────────────────────

/// AEL에서 유효한 순서인지 검사.
fn isValidAelOrder(resident: ?*Active, newcomer: ?*Active) bool {
    if (@abs(newcomer.?.curr_x - resident.?.curr_x) > Eps) {
        return newcomer.?.curr_x > resident.?.curr_x;
    }
    // 같은 curr_x → turning direction 비교: resident.top → newcomer.bot → newcomer.top
    const i = crossProductSign(resident.?.top, newcomer.?.bot, newcomer.?.top);
    if (i != 0) return i < 0;

    // collinear edges — 다음 turning direction 확인
    if (!isMaximaE(resident) and resident.?.top.y > newcomer.?.top.y) {
        const nv = nextVertex(resident);
        return crossProductSign(newcomer.?.bot, resident.?.top, nv.?.pt) <= 0;
    } else if (!isMaximaE(newcomer) and newcomer.?.top.y > resident.?.top.y) {
        const nv = nextVertex(newcomer);
        return crossProductSign(newcomer.?.bot, newcomer.?.top, nv.?.pt) >= 0;
    }

    const y = newcomer.?.bot.y;
    const newcomerIsLeft = newcomer.?.is_left_bound;

    if (@abs(resident.?.bot.y - y) > Eps or @abs(resident.?.local_min.?.vertex.?.pt.y - y) > Eps) {
        return newcomerIsLeft;
    } else if (resident.?.is_left_bound != newcomerIsLeft) {
        return newcomerIsLeft;
    } else if (isCollinear(
        prevPrevVertex(resident).?.pt,
        resident.?.bot,
        resident.?.top,
    )) {
        return true;
    } else {
        return (crossProductSign(
            prevPrevVertex(resident).?.pt,
            newcomer.?.bot,
            prevPrevVertex(newcomer).?.pt,
        ) > 0) == newcomerIsLeft;
    }
}

/// AEL에 왼쪽 엣지 삽입.
fn insertLeftEdge(cb: *ClipperBase, e: *Active) void {
    if (cb.actives == null) {
        e.prev_in_ael = null;
        e.next_in_ael = null;
        cb.actives = e;
    } else if (!isValidAelOrder(cb.actives, e)) {
        e.prev_in_ael = null;
        e.next_in_ael = cb.actives;
        cb.actives.?.prev_in_ael = e;
        cb.actives = e;
    } else {
        var e2 = cb.actives;
        while (e2.?.next_in_ael != null and isValidAelOrder(e2.?.next_in_ael, e)) {
            e2 = e2.?.next_in_ael;
        }
        if (e2.?.join_with == .Right) {
            e2 = e2.?.next_in_ael;
        }
        if (e2 == null) return;
        e.next_in_ael = e2.?.next_in_ael;
        if (e2.?.next_in_ael != null) {
            e2.?.next_in_ael.?.prev_in_ael = e;
        }
        e.prev_in_ael = e2;
        e2.?.next_in_ael = e;
    }
}

/// AEL에 오른쪽 엣지 삽입.
fn insertRightEdge(e: *Active, e2: *Active) void {
    e2.next_in_ael = e.next_in_ael;
    if (e.next_in_ael != null) {
        e.next_in_ael.?.prev_in_ael = e2;
    }
    e2.prev_in_ael = e;
    e.next_in_ael = e2;
}

/// AEL에서 엣지 제거.
fn deleteFromAEL(cb: *ClipperBase, e: *Active) void {
    const prev = e.prev_in_ael;
    const nxt = e.next_in_ael;
    if (prev == null and nxt == null and e != cb.actives) {
        return; // 이미 삭제됨
    }
    if (prev != null) {
        prev.next_in_ael = nxt;
    } else {
        cb.actives = nxt;
    }
    if (nxt != null) {
        nxt.prev_in_ael = prev;
    }
    e.prev_in_ael = null;
    e.next_in_ael = null;
}

/// AEL에서 두 엣지 위치 교환 (precondition: e1 is immediately to the left of e2).
fn swapPositionsInAEL(cb: *ClipperBase, e1: *Active, e2: *Active) void {
    const nxt = e2.next_in_ael;
    if (nxt != null) {
        nxt.prev_in_ael = e1;
    }
    const prev = e1.prev_in_ael;
    if (prev != null) {
        prev.next_in_ael = e2;
    }
    e2.prev_in_ael = prev;
    e2.next_in_ael = e1;
    e1.prev_in_ael = e2;
    e1.next_in_ael = nxt;
    if (e2.prev_in_ael == null) {
        cb.actives = e2;
    }
}

/// 수평 엣지를 SEL에 푸시.
fn pushHorz(cb: *ClipperBase, e: *Active) void {
    e.next_in_sel = cb.sel;
    cb.sel = e;
}

/// SEL에서 수평 엣지 팝.
fn popHorz(cb: *ClipperBase, e: **?*Active) bool {
    if (cb.sel == null) return false;
    e.* = cb.sel;
    cb.sel = cb.sel.?.next_in_sel;
    return true;
}

// ──── Wind Count + Contribution ──────────────────────────────────────────────

/// 닫힌 경로 기여 여부.
fn isContributingClosed(cb: *ClipperBase, e: ?*Active) bool {
    switch (cb.fillrule) {
        .EvenOdd => {},
        .NonZero => {
            if (@abs(e.?.wind_cnt) != 1) return false;
        },
        .Positive => {
            if (e.?.wind_cnt != 1) return false;
        },
        .Negative => {
            if (e.?.wind_cnt != -1) return false;
        },
    }

    return switch (cb.cliptype) {
        .NoClip => false,
        .Intersection => switch (cb.fillrule) {
            .Positive => e.?.wind_cnt2 > 0,
            .Negative => e.?.wind_cnt2 < 0,
            else => e.?.wind_cnt2 != 0,
        },
        .Union => switch (cb.fillrule) {
            .Positive => e.?.wind_cnt2 <= 0,
            .Negative => e.?.wind_cnt2 >= 0,
            else => e.?.wind_cnt2 == 0,
        },
        .Difference => blk: {
            const result = switch (cb.fillrule) {
                .Positive => e.?.wind_cnt2 <= 0,
                .Negative => e.?.wind_cnt2 >= 0,
                else => e.?.wind_cnt2 == 0,
            };
            break :blk if (getPolyType(e) == .Subject) result else !result;
        },
        .Xor => true,
    };
}

/// 열린 경로 기여 여부.
fn isContributingOpen(cb: *ClipperBase, e: ?*Active) bool {
    var is_in_clip = false;
    var is_in_subj = false;
    switch (cb.fillrule) {
        .Positive => {
            is_in_clip = e.?.wind_cnt2 > 0;
            is_in_subj = e.?.wind_cnt > 0;
        },
        .Negative => {
            is_in_clip = e.?.wind_cnt2 < 0;
            is_in_subj = e.?.wind_cnt < 0;
        },
        else => {
            is_in_clip = e.?.wind_cnt2 != 0;
            is_in_subj = e.?.wind_cnt != 0;
        },
    }

    switch (cb.cliptype) {
        .Intersection => return is_in_clip,
        .Union => return !is_in_subj and !is_in_clip,
        else => return !is_in_clip,
    }
}

/// 닫힌 경로 wind count 설정.
fn setWindCountForClosedPathEdge(cb: *ClipperBase, e: *Active) void {
    // AEL에서 같은 PolyType의 가장 가까운 닫힌 경로 엣지 찾기 (왼쪽으로)
    const pt = getPolyType(e);
    var e2 = e.prev_in_ael;
    while (e2 != null and (getPolyType(e2) != pt or isOpen(e2))) {
        e2 = e2.?.prev_in_ael;
    }

    if (e2 == null) {
        e.wind_cnt = e.wind_dx;
        e2 = cb.actives;
    } else if (cb.fillrule == .EvenOdd) {
        e.wind_cnt = e.wind_dx;
        e.wind_cnt2 = e2.?.wind_cnt2;
        e2 = e2.?.next_in_ael;
    } else {
        // NonZero, positive, or negative
        if (e2.?.wind_cnt * e2.?.wind_dx < 0) {
            // 반대 방향 → e는 e2 바깥
            if (@abs(e2.?.wind_cnt) > 1) {
                if (e2.?.wind_dx * e.wind_dx < 0) {
                    e.wind_cnt = e2.?.wind_cnt;
                } else {
                    e.wind_cnt = e2.?.wind_cnt + e.wind_dx;
                }
            } else {
                e.wind_cnt = e.wind_dx;
            }
        } else {
            // e는 e2 안쪽
            if (e2.?.wind_dx * e.wind_dx < 0) {
                e.wind_cnt = e2.?.wind_cnt;
            } else {
                e.wind_cnt = e2.?.wind_cnt + e.wind_dx;
            }
        }
        e.wind_cnt2 = e2.?.wind_cnt2;
        e2 = e2.?.next_in_ael;
    }

    // wind_cnt2 업데이트
    switch (cb.fillrule) {
        .EvenOdd => {
            while (e2 != e) {
                if (getPolyType(e2) != pt and !isOpen(e2)) {
                    e.wind_cnt2 = if (e.wind_cnt2 == 0) @as(i32, 1) else 0;
                }
                e2 = e2.?.next_in_ael;
            }
        },
        else => {
            while (e2 != e) {
                if (getPolyType(e2) != pt and !isOpen(e2)) {
                    e.wind_cnt2 += e2.?.wind_dx;
                }
                e2 = e2.?.next_in_ael;
            }
        },
    }
}

/// 열린 경로 wind count 설정.
fn setWindCountForOpenPathEdge(cb: *ClipperBase, e: *Active) void {
    if (cb.fillrule == .EvenOdd) {
        var cnt1: i32 = 0;
        var cnt2: i32 = 0;
        var e2 = cb.actives;
        while (e2 != e) {
            if (getPolyType(e2) == .Clip) {
                cnt2 += 1;
            } else if (!isOpen(e2)) {
                cnt1 += 1;
            }
            e2 = e2.?.next_in_ael;
        }
        e.wind_cnt = if (isOdd(cnt1)) @as(i32, 1) else 0;
        e.wind_cnt2 = if (isOdd(cnt2)) @as(i32, 1) else 0;
    } else {
        var e2 = cb.actives;
        while (e2 != e) {
            if (getPolyType(e2) == .Clip) {
                e.wind_cnt2 += e2.?.wind_dx;
            } else if (!isOpen(e2)) {
                e.wind_cnt += e2.?.wind_dx;
            }
            e2 = e2.?.next_in_ael;
        }
    }
}

// ──── Output path construction ───────────────────────────────────────────────

/// 새 출력 레코드 생성.
fn newOutRec(cb: *ClipperBase, allocator: std.mem.Allocator) ?*OutRec {
    const rec = allocator.create(OutRec) catch return null;
    rec.idx = cb.outrec_list.items.len;
    rec.path = std.ArrayList(Point).init(allocator);
    cb.outrec_list.append(allocator, rec) catch {
        allocator.destroy(rec);
        return null;
    };
    return rec;
}

/// 엣지 설정.
fn setSides(outrec: *OutRec, start_edge: ?*Active, end_edge: ?*Active) void {
    outrec.front_edge = start_edge;
    outrec.back_edge = end_edge;
}

/// 오름차순 엣지인지.
inline fn outrecIsAscending(hotEdge: ?*Active) bool {
    return hotEdge == hotEdge.?.outrec.?.front_edge;
}

/// 앞/뒤 엣지 교환.
fn swapFrontBackSides(outrec: *OutRec) void {
    const tmp = outrec.front_edge;
    outrec.front_edge = outrec.back_edge;
    outrec.back_edge = tmp;
    if (outrec.pts != null) {
        outrec.pts = outrec.pts.?.next;
    }
}

/// 출력 레코드 연결 해제.
fn uncoupleOutRec(ae: ?*Active) void {
    const outrec = ae.?.outrec;
    if (outrec == null) return;
    if (outrec.?.front_edge != null) outrec.?.front_edge.?.outrec = null;
    if (outrec.?.back_edge != null) outrec.?.back_edge.?.outrec = null;
    outrec.?.front_edge = null;
    outrec.?.back_edge = null;
}

/// 출력 점 추가.
fn addOutPt(cb: *ClipperBase, e: ?*Active, pt: Point, allocator: std.mem.Allocator) ?*OutPt {
    _ = cb;
    const outrec = e.?.outrec orelse return null;
    const to_front = isFront(e);
    const op_front = outrec.pts;
    if (op_front == null) return null;
    const op_back = op_front.?.next;

    if (to_front) {
        if (op_front.?.pt.x == pt.x and op_front.?.pt.y == pt.y) return op_front;
    } else if (op_back.?.pt.x == pt.x and op_back.?.pt.y == pt.y) {
        return op_back;
    }

    const new_op = allocator.create(OutPt) catch return null;
    new_op.pt = pt;
    new_op.outrec = outrec;
    new_op.next = null;
    new_op.prev = null;
    new_op.horz = null;

    op_back.?.prev = new_op;
    new_op.prev = op_front;
    new_op.next = op_back;
    op_front.?.next = new_op;
    if (to_front) {
        outrec.pts = new_op;
    }
    return new_op;
}

/// 로컬 최소 폴리곤 추가.
fn addLocalMinPoly(
    cb: *ClipperBase,
    e1: ?*Active,
    e2: ?*Active,
    pt: Point,
    is_new: bool,
    allocator: std.mem.Allocator,
) ?*OutPt {
    const outrec = newOutRec(cb, allocator) orelse return null;
    e1.?.outrec = outrec;
    e2.?.outrec = outrec;

    if (isOpen(e1)) {
        outrec.owner = null;
        outrec.is_open = true;
        if (e1.?.wind_dx > 0) {
            setSides(outrec, e1, e2);
        } else {
            setSides(outrec, e2, e1);
        }
    } else {
        const prevHotEdge = getPrevHotEdge(e1);
        if (prevHotEdge != null) {
            if (outrecIsAscending(prevHotEdge) == is_new) {
                setSides(outrec, e2, e1);
            } else {
                setSides(outrec, e1, e2);
            }
        } else {
            outrec.owner = null;
            if (is_new) {
                setSides(outrec, e1, e2);
            } else {
                setSides(outrec, e2, e1);
            }
        }
    }

    const op = allocator.create(OutPt) catch return null;
    op.pt = pt;
    op.outrec = outrec;
    op.next = op;
    op.prev = op;
    op.horz = null;
    outrec.pts = op;
    return op;
}

/// 로컬 최대 폴리곤 추가.
fn addLocalMaxPoly(
    cb: *ClipperBase,
    e1: ?*Active,
    e2: ?*Active,
    pt: Point,
    allocator: std.mem.Allocator,
) ?*OutPt {
    if (isJoined(e1)) split(cb, e1, pt, allocator);
    if (isJoined(e2)) split(cb, e2, pt, allocator);

    if (isFront(e1) == isFront(e2)) {
        if (isOpenEndE(e1)) {
            swapFrontBackSides(e1.?.outrec);
        } else if (isOpenEndE(e2)) {
            swapFrontBackSides(e2.?.outrec);
        } else {
            cb.succeeded = false;
            return null;
        }
    }

    var result = addOutPt(cb, e1, pt, allocator);
    if (e1.?.outrec == e2.?.outrec) {
        const outrec = e1.?.outrec;
        outrec.?.pts = result;
        uncoupleOutRec(e1);
        result = outrec.?.pts;
        if (outrec.?.owner != null and outrec.?.owner.?.front_edge == null) {
            outrec.?.owner = getRealOutRec(outrec.?.owner);
        }
    } else if (isOpen(e1)) {
        if (e1.?.wind_dx < 0) {
            joinOutrecPaths(cb, e1, e2);
        } else {
            joinOutrecPaths(cb, e2, e1);
        }
    } else if (e1.?.outrec.?.idx < e2.?.outrec.?.idx) {
        joinOutrecPaths(cb, e1, e2);
    } else {
        joinOutrecPaths(cb, e2, e1);
    }
    return result;
}

/// 출력 경로 결합.
fn joinOutrecPaths(cb: *ClipperBase, e1: ?*Active, e2: ?*Active) void {
    _ = cb;
    const p1_st = e1.?.outrec.?.pts;
    const p2_st = e2.?.outrec.?.pts;
    const p1_end = p1_st.?.next;
    const p2_end = p2_st.?.next;

    if (isFront(e1)) {
        p2_end.?.prev = p1_st;
        p1_st.?.next = p2_end;
        p2_st.?.next = p1_end;
        p1_end.?.prev = p2_st;
        e1.?.outrec.?.pts = p2_st;
        e1.?.outrec.?.front_edge = e2.?.outrec.?.front_edge;
        if (e1.?.outrec.?.front_edge != null) {
            e1.?.outrec.?.front_edge.?.outrec = e1.?.outrec;
        }
    } else {
        p1_end.?.prev = p2_st;
        p2_st.?.next = p1_end;
        p1_st.?.next = p2_end;
        p2_end.?.prev = p1_st;
        e1.?.outrec.?.back_edge = e2.?.outrec.?.back_edge;
        if (e1.?.outrec.?.back_edge != null) {
            e1.?.outrec.?.back_edge.?.outrec = e1.?.outrec;
        }
    }

    e2.?.outrec.?.front_edge = null;
    e2.?.outrec.?.back_edge = null;
    e2.?.outrec.?.pts = null;

    if (isOpenEndE(e1)) {
        e2.?.outrec.?.pts = e1.?.outrec.?.pts;
        e1.?.outrec.?.pts = null;
    } else {
        // SetOwner with cycle detection
        var owner = e1.?.outrec;
        while (owner != null and owner.?.pts == null) {
            owner = owner.?.owner;
        }
        var tmp = owner;
        while (tmp != null and tmp != e2.?.outrec) {
            tmp = tmp.?.owner;
        }
        if (tmp != null) {
            owner = e2.?.outrec.?.owner;
        }
        e2.?.outrec.?.owner = owner;
    }

    e1.?.outrec = null;
    e2.?.outrec = null;
}

/// 열린 경로 시작.
fn startOpenPath(
    cb: *ClipperBase,
    e: ?*Active,
    pt: Point,
    allocator: std.mem.Allocator,
) ?*OutPt {
    const outrec = newOutRec(cb, allocator) orelse return null;
    outrec.is_open = true;
    if (e.?.wind_dx > 0) {
        outrec.front_edge = e;
        outrec.back_edge = null;
    } else {
        outrec.front_edge = null;
        outrec.back_edge = e;
    }
    e.?.outrec = outrec;

    const op = allocator.create(OutPt) catch return null;
    op.pt = pt;
    op.outrec = outrec;
    op.next = op;
    op.prev = op;
    op.horz = null;
    outrec.pts = op;
    return op;
}

/// 실제 출력 레코드 찾기.
fn getRealOutRec(outrec: ?*OutRec) ?*OutRec {
    var rec = outrec;
    while (rec != null and rec.?.pts == null) {
        rec = rec.?.owner;
    }
    return rec;
}

/// 엣지 분할.
fn split(cb: *ClipperBase, e: ?*Active, pt: Point, allocator: std.mem.Allocator) void {
    if (e.?.join_with == .Right) {
        e.?.join_with = .NoJoin;
        e.?.next_in_ael.?.join_with = .NoJoin;
        _ = addLocalMinPoly(cb, e, e.?.next_in_ael, pt, true, allocator);
    } else {
        e.?.join_with = .NoJoin;
        e.?.prev_in_ael.?.join_with = .NoJoin;
        _ = addLocalMinPoly(cb, e.?.prev_in_ael, e, pt, true, allocator);
    }
}

// ──── InsertLocalMinimaIntoAEL + CheckJoinLeft/Right ─────────────────────────

/// 왼쪽 조인 확인.
fn checkJoinLeft(
    cb: *ClipperBase,
    e: ?*Active,
    pt: Point,
    check_curr_x: bool,
    allocator: std.mem.Allocator,
) void {
    const prev = e.?.prev_in_ael;
    if (prev == null or
        !isHotEdge(e) or
        !isHotEdge(prev) or
        isHorizontalE(e) or
        isHorizontalE(prev) or
        isOpen(e) or
        isOpen(prev))
    {
        return;
    }
    if ((pt.y < e.?.top.y + 2 or pt.y < prev.?.top.y + 2) and
        (e.?.bot.y > pt.y or prev.?.bot.y > pt.y))
    {
        return;
    }
    if (check_curr_x) {
        if (perpendicDistFromLineSqrd(pt, prev.?.bot, prev.?.top) > 0.25) return;
    } else if (e.?.curr_x != prev.?.curr_x) {
        return;
    }
    if (!isCollinear(e.?.top, pt, prev.?.top)) return;

    if (e.?.outrec.?.idx == prev.?.outrec.?.idx) {
        _ = addLocalMaxPoly(cb, prev, e, pt, allocator);
    } else if (e.?.outrec.?.idx < prev.?.outrec.?.idx) {
        joinOutrecPaths(cb, e, prev);
    } else {
        joinOutrecPaths(cb, prev, e);
    }
    prev.?.join_with = .Right;
    e.?.join_with = .Left;
}

/// 오른쪽 조인 확인.
fn checkJoinRight(
    cb: *ClipperBase,
    e: ?*Active,
    pt: Point,
    check_curr_x: bool,
    allocator: std.mem.Allocator,
) void {
    const nxt = e.?.next_in_ael;
    if (nxt == null or
        !isHotEdge(e) or
        !isHotEdge(nxt) or
        isHorizontalE(e) or
        isHorizontalE(nxt) or
        isOpen(e) or
        isOpen(nxt))
    {
        return;
    }
    if ((pt.y < e.?.top.y + 2 or pt.y < nxt.?.top.y + 2) and
        (e.?.bot.y > pt.y or nxt.?.bot.y > pt.y))
    {
        return;
    }
    if (check_curr_x) {
        if (perpendicDistFromLineSqrd(pt, nxt.?.bot, nxt.?.top) > 0.35) return;
    } else if (e.?.curr_x != nxt.?.curr_x) {
        return;
    }
    if (!isCollinear(e.?.top, pt, nxt.?.top)) return;

    if (e.?.outrec.?.idx == nxt.?.outrec.?.idx) {
        _ = addLocalMaxPoly(cb, e, nxt, pt, allocator);
    } else if (e.?.outrec.?.idx < nxt.?.outrec.?.idx) {
        joinOutrecPaths(cb, e, nxt);
    } else {
        joinOutrecPaths(cb, nxt, e);
    }
    e.?.join_with = .Right;
    nxt.?.join_with = .Left;
}

/// 로컬 최소값을 AEL에 삽입.
fn insertLocalMinimaIntoAEL(
    cb: *ClipperBase,
    bot_y: f64,
    allocator: std.mem.Allocator,
) void {
    while (true) {
        var lm: ?*LocalMinima = null;
        if (!popLocalMinima(cb, bot_y, &lm)) break;

        var left_bound: ?*Active = null;
        var right_bound: ?*Active = null;

        if (!hasFlag(lm.?.vertex, .OpenStart)) {
            left_bound = allocator.create(Active) catch return;
            left_bound.?.bot = lm.?.vertex.?.pt;
            left_bound.?.curr_x = left_bound.?.bot.x;
            left_bound.?.wind_dx = -1;
            left_bound.?.vertex_top = lm.?.vertex.?.prev;
            left_bound.?.top = left_bound.?.vertex_top.?.pt;
            left_bound.?.local_min = lm;
            setDx(left_bound);
        }

        if (!hasFlag(lm.?.vertex, .OpenEnd)) {
            right_bound = allocator.create(Active) catch return;
            right_bound.?.bot = lm.?.vertex.?.pt;
            right_bound.?.curr_x = right_bound.?.bot.x;
            right_bound.?.wind_dx = 1;
            right_bound.?.vertex_top = lm.?.vertex.?.next;
            right_bound.?.top = right_bound.?.vertex_top.?.pt;
            right_bound.?.local_min = lm;
            setDx(right_bound);
        }

        // swap left/right if needed (descending bound should be on the left)
        if (left_bound != null and right_bound != null) {
            if (isHorizontalE(left_bound)) {
                if (isHeadingRightHorz(left_bound)) {
                    const tmp = left_bound;
                    left_bound = right_bound;
                    right_bound = tmp;
                }
            } else if (isHorizontalE(right_bound)) {
                if (isHeadingLeftHorz(right_bound)) {
                    const tmp = left_bound;
                    left_bound = right_bound;
                    right_bound = tmp;
                }
            } else if (left_bound.?.dx < right_bound.?.dx) {
                const tmp = left_bound;
                left_bound = right_bound;
                right_bound = tmp;
            }
        } else if (left_bound == null) {
            left_bound = right_bound;
            right_bound = null;
        }

        if (left_bound == null) continue;
        left_bound.?.is_left_bound = true;
        insertLeftEdge(cb, left_bound.?);

        var contributing = false;
        if (isOpen(left_bound)) {
            setWindCountForOpenPathEdge(cb, left_bound.?);
            contributing = isContributingOpen(cb, left_bound);
        } else {
            setWindCountForClosedPathEdge(cb, left_bound.?);
            contributing = isContributingClosed(cb, left_bound);
        }

        if (right_bound != null) {
            right_bound.?.is_left_bound = false;
            right_bound.?.wind_cnt = left_bound.?.wind_cnt;
            right_bound.?.wind_cnt2 = left_bound.?.wind_cnt2;
            insertRightEdge(left_bound.?, right_bound.?);

            if (contributing) {
                _ = addLocalMinPoly(cb, left_bound, right_bound, left_bound.?.bot, true, allocator);
                if (!isHorizontalE(left_bound)) {
                    checkJoinLeft(cb, left_bound, left_bound.?.bot, false, allocator);
                }
            }

            // intersect right_bound with AEL neighbors to correct ordering
            var next_ae = right_bound.?.next_in_ael;
            while (next_ae != null and isValidAelOrder(next_ae, right_bound)) {
                intersectEdges(cb, right_bound, next_ae, right_bound.?.bot, allocator);
                swapPositionsInAEL(cb, right_bound, next_ae);
                next_ae = right_bound.?.next_in_ael;
            }

            if (isHorizontalE(right_bound)) {
                pushHorz(cb, right_bound.?);
            } else {
                checkJoinRight(cb, right_bound, right_bound.?.bot, false, allocator);
                insertScanline(cb, right_bound.?.top.y, allocator);
            }
        } else if (contributing) {
            _ = startOpenPath(cb, left_bound, left_bound.?.bot, allocator);
        }

        if (isHorizontalE(left_bound)) {
            pushHorz(cb, left_bound.?);
        } else {
            insertScanline(cb, left_bound.?.top.y, allocator);
        }
    }
}

// ──── IntersectEdges (core) + helpers ────────────────────────────────────────

/// 출력 레코드 교환.
fn swapOutrecs(e1: ?*Active, e2: ?*Active) void {
    const or1 = e1.?.outrec;
    const or2 = e2.?.outrec;
    if (or1 == or2) {
        const e = or1.?.front_edge;
        or1.?.front_edge = or1.?.back_edge;
        or1.?.back_edge = e;
        return;
    }
    if (or1 != null) {
        if (e1 == or1.?.front_edge) {
            or1.?.front_edge = e2;
        } else {
            or1.?.back_edge = e2;
        }
    }
    if (or2 != null) {
        if (e2 == or2.?.front_edge) {
            or2.?.front_edge = e1;
        } else {
            or2.?.back_edge = e1;
        }
    }
    e1.?.outrec = or2;
    e2.?.outrec = or1;
}

/// 일치하는 로컬 최소값 엣지 찾기.
fn findEdgeWithMatchingLocMin(e: ?*Active) ?*Active {
    var result = e.?.next_in_ael;
    while (result != null) {
        if (result.?.local_min == e.?.local_min) return result;
        if (!isHorizontalE(result) and !(e.?.bot.x == result.?.bot.x and e.?.bot.y == result.?.bot.y)) {
            result = null;
        } else {
            result = result.?.next_in_ael;
        }
    }
    result = e.?.prev_in_ael;
    while (result != null) {
        if (result.?.local_min == e.?.local_min) return result;
        if (!isHorizontalE(result) and !(e.?.bot.x == result.?.bot.x and e.?.bot.y == result.?.bot.y)) {
            return null;
        }
        result = result.?.prev_in_ael;
    }
    return result;
}

/// Z 콜백 호출 (2D에서는 no-op).
fn setZ(cb: *ClipperBase, e1: ?*Active, e2: ?*Active) void {
    _ = cb;
    _ = e1;
    _ = e2;
}

/// 엣지 교차 처리.
fn intersectEdges(
    cb: *ClipperBase,
    e1: ?*Active,
    e2: ?*Active,
    pt: Point,
    allocator: std.mem.Allocator,
) void {
    // ── OPEN PATH INTERSECTIONS ──
    if (cb.has_open_paths and (isOpen(e1) or isOpen(e2))) {
        if (isOpen(e1) and isOpen(e2)) return;
        var edge_o: ?*Active = null;
        var edge_c: ?*Active = null;
        if (isOpen(e1)) {
            edge_o = e1;
            edge_c = e2;
        } else {
            edge_o = e2;
            edge_c = e1;
        }
        if (isJoined(edge_c)) {
            split(cb, edge_c, pt, allocator);
        }
        if (@abs(edge_c.?.wind_cnt) != 1) return;

        switch (cb.cliptype) {
            .Union => {
                if (!isHotEdge(edge_c)) return;
            },
            else => {
                if (edge_c.?.local_min.?.polytype == .Subject) return;
            },
        }

        switch (cb.fillrule) {
            .Positive => {
                if (edge_c.?.wind_cnt != 1) return;
            },
            .Negative => {
                if (edge_c.?.wind_cnt != -1) return;
            },
            else => {
                if (@abs(edge_c.?.wind_cnt) != 1) return;
            },
        }

        // toggle contribution
        var result_op: ?*OutPt = null;
        if (isHotEdge(edge_o)) {
            result_op = addOutPt(cb, edge_o, pt, allocator);
            if (isFront(edge_o)) {
                edge_o.?.outrec.?.front_edge = null;
            } else {
                edge_o.?.outrec.?.back_edge = null;
            }
            edge_o.?.outrec = null;
        } else if (pt.x == edge_o.?.local_min.?.vertex.?.pt.x and
            pt.y == edge_o.?.local_min.?.vertex.?.pt.y and
            !isOpenEnd(edge_o.?.local_min.?.vertex))
        {
            const e3 = findEdgeWithMatchingLocMin(edge_o);
            if (e3 != null and isHotEdge(e3)) {
                edge_o.?.outrec = e3.?.outrec;
                if (edge_o.?.wind_dx > 0) {
                    setSides(e3.?.outrec, edge_o, e3);
                } else {
                    setSides(e3.?.outrec, e3, edge_o);
                }
                return;
            } else {
                result_op = startOpenPath(cb, edge_o, pt, allocator);
            }
        } else {
            result_op = startOpenPath(cb, edge_o, pt, allocator);
        }
        // Z callback (2D: no-op)
        return;
    }

    // ── CLOSED PATH INTERSECTIONS ──
    if (isJoined(e1)) split(cb, e1, pt, allocator);
    if (isJoined(e2)) split(cb, e2, pt, allocator);

    // update winding counts
    var old_e1_windcnt: i32 = undefined;
    var old_e2_windcnt: i32 = undefined;
    if (getPolyType(e1) == getPolyType(e2)) {
        if (cb.fillrule == .EvenOdd) {
            old_e1_windcnt = e1.?.wind_cnt;
            e1.?.wind_cnt = e2.?.wind_cnt;
            e2.?.wind_cnt = old_e1_windcnt;
        } else {
            if (e1.?.wind_cnt + e2.?.wind_dx == 0) {
                e1.?.wind_cnt = -e1.?.wind_cnt;
            } else {
                e1.?.wind_cnt += e2.?.wind_dx;
            }
            if (e2.?.wind_cnt - e1.?.wind_dx == 0) {
                e2.?.wind_cnt = -e2.?.wind_cnt;
            } else {
                e2.?.wind_cnt -= e1.?.wind_dx;
            }
        }
    } else {
        if (cb.fillrule != .EvenOdd) {
            e1.?.wind_cnt2 += e2.?.wind_dx;
            e2.?.wind_cnt2 -= e1.?.wind_dx;
        } else {
            e1.?.wind_cnt2 = if (e1.?.wind_cnt2 == 0) @as(i32, 1) else 0;
            e2.?.wind_cnt2 = if (e2.?.wind_cnt2 == 0) @as(i32, 1) else 0;
        }
    }

    // compute old winding counts (used for contribution check)
    switch (cb.fillrule) {
        .EvenOdd, .NonZero => {
            old_e1_windcnt = @intCast(@abs(e1.?.wind_cnt));
            old_e2_windcnt = @intCast(@abs(e2.?.wind_cnt));
        },
        else => {
            if (cb.fillrule == cb.fillpos) {
                old_e1_windcnt = e1.?.wind_cnt;
                old_e2_windcnt = e2.?.wind_cnt;
            } else {
                old_e1_windcnt = -e1.?.wind_cnt;
                old_e2_windcnt = -e2.?.wind_cnt;
            }
        },
    }

    const e1_windcnt_in_01 = old_e1_windcnt == 0 or old_e1_windcnt == 1;
    const e2_windcnt_in_01 = old_e2_windcnt == 0 or old_e2_windcnt == 1;

    if ((!isHotEdge(e1) and !e1_windcnt_in_01) or (!isHotEdge(e2) and !e2_windcnt_in_01)) {
        return;
    }

    // ── PROCESS INTERSECTION ──
    var result_op: ?*OutPt = null;
    if (isHotEdge(e1) and isHotEdge(e2)) {
        if ((old_e1_windcnt != 0 and old_e1_windcnt != 1) or
            (old_e2_windcnt != 0 and old_e2_windcnt != 1) or
            (getPolyType(e1) != getPolyType(e2) and cb.cliptype != .Xor))
        {
            result_op = addLocalMaxPoly(cb, e1, e2, pt, allocator);
        } else if (isFront(e1) or (e1.?.outrec == e2.?.outrec)) {
            result_op = addLocalMaxPoly(cb, e1, e2, pt, allocator);
            _ = addLocalMinPoly(cb, e1, e2, pt, false, allocator);
        } else {
            result_op = addOutPt(cb, e1, pt, allocator);
            _ = addOutPt(cb, e2, pt, allocator);
            swapOutrecs(e1, e2);
        }
    } else if (isHotEdge(e1)) {
        result_op = addOutPt(cb, e1, pt, allocator);
        swapOutrecs(e1, e2);
    } else if (isHotEdge(e2)) {
        result_op = addOutPt(cb, e2, pt, allocator);
        swapOutrecs(e1, e2);
    } else {
        var e1Wc2: i32 = undefined;
        var e2Wc2: i32 = undefined;
        switch (cb.fillrule) {
            .EvenOdd, .NonZero => {
                e1Wc2 = @intCast(@abs(e1.?.wind_cnt2));
                e2Wc2 = @intCast(@abs(e2.?.wind_cnt2));
            },
            else => {
                if (cb.fillrule == cb.fillpos) {
                    e1Wc2 = e1.?.wind_cnt2;
                    e2Wc2 = e2.?.wind_cnt2;
                } else {
                    e1Wc2 = -e1.?.wind_cnt2;
                    e2Wc2 = -e2.?.wind_cnt2;
                }
            },
        }

        if (!isSamePolyType(e1, e2)) {
            result_op = addLocalMinPoly(cb, e1, e2, pt, false, allocator);
        } else if (old_e1_windcnt == 1 and old_e2_windcnt == 1) {
            switch (cb.cliptype) {
                .Union => {
                    if (e1Wc2 <= 0 and e2Wc2 <= 0) {
                        result_op = addLocalMinPoly(cb, e1, e2, pt, false, allocator);
                    }
                },
                .Difference => {
                    if ((getPolyType(e1) == .Clip and e1Wc2 > 0 and e2Wc2 > 0) or
                        (getPolyType(e1) == .Subject and e1Wc2 <= 0 and e2Wc2 <= 0))
                    {
                        result_op = addLocalMinPoly(cb, e1, e2, pt, false, allocator);
                    }
                },
                .Xor => {
                    result_op = addLocalMinPoly(cb, e1, e2, pt, false, allocator);
                },
                else => {
                    if (e1Wc2 > 0 and e2Wc2 > 0) {
                        result_op = addLocalMinPoly(cb, e1, e2, pt, false, allocator);
                    }
                },
            }
        }
    }
}

// ============================================================================
// Stage 4: Scanline Loop + Horizontal Processing + Output Assembly
// Odin clipper.odin lines 2003~2543 포팅
// ============================================================================

// ──── Merge sort helpers for SEL ──────────────────────────────────────────────

/// SEL에서 엣지 추출. 다음 엣지 반환.
fn extractFromSEL(ae: *Active) ?*Active {
    const res = ae.next_in_sel orelse return null;
    res.prev_in_sel = ae.prev_in_sel;
    if (ae.prev_in_sel) |prev| {
        prev.next_in_sel = res;
    }
    return res;
}

/// SEL에 ae1을 ae2 앞에 삽입.
fn insert1Before2InSEL(ae1: *Active, ae2: *Active) void {
    ae1.prev_in_sel = ae2.prev_in_sel;
    if (ae1.prev_in_sel) |prev| {
        prev.next_in_sel = ae1;
    }
    ae1.next_in_sel = ae2;
    ae2.prev_in_sel = ae1;
}

/// 현재 X 조정 후 SEL에 복사.
fn adjustCurrXAndCopyToSEL(cb: *ClipperBase, top_y: f64) void {
    var e = cb.actives orelse return;
    cb.sel = e;
    while (e) |active| {
        active.prev_in_sel = active.prev_in_ael;
        active.next_in_sel = active.next_in_ael;
        active.jump = active.next_in_sel;
        active.curr_x = topX(active.dx, active.bot, active.top, top_y);
        e = active.next_in_ael;
    }
}

// ──── Intersect list building ─────────────────────────────────────────────────

/// 새 교차점 노드 추가.
fn addNewIntersectNode(cb: *ClipperBase, e1: ?*Active, e2: ?*Active, top_y: f64, allocator: std.mem.Allocator) !void {
    var ip: Point = .{ .x = 0, .y = 0 };
    const got_intersect = getLineIntersectPt(
        e1.?.bot,
        e1.?.top,
        e2.?.bot,
        e2.?.top,
        &ip,
    );

    if (!got_intersect) {
        ip.x = e1.?.curr_x;
        ip.y = top_y;
    }

    // clamp intersection to scanbeam bounds
    if (ip.y > cb.bot_y or ip.y < top_y) {
        const abs_dx1 = @abs(e1.?.dx);
        const abs_dx2 = @abs(e2.?.dx);
        if (abs_dx1 > 100 and abs_dx2 > 100) {
            if (abs_dx1 > abs_dx2) {
                ip = getClosestPointOnSegment(ip, e1.?.bot, e1.?.top);
            } else {
                ip = getClosestPointOnSegment(ip, e2.?.bot, e2.?.top);
            }
        } else if (abs_dx1 > 100) {
            ip = getClosestPointOnSegment(ip, e1.?.bot, e1.?.top);
        } else if (abs_dx2 > 100) {
            ip = getClosestPointOnSegment(ip, e2.?.bot, e2.?.top);
        } else {
            if (ip.y < top_y) {
                ip.y = top_y;
            } else {
                ip.y = cb.bot_y;
            }
            if (abs_dx1 < abs_dx2) {
                ip.x = topX(e1.?.dx, e1.?.bot, e1.?.top, ip.y);
            } else {
                ip.x = topX(e2.?.dx, e2.?.bot, e2.?.top, ip.y);
            }
        }
    }

    try cb.intersect_nodes.append(allocator, .{
        .pt = ip,
        .edge1 = e1,
        .edge2 = e2,
    });
}

/// 교차점 정렬 비교 - Y 내림차순, X 오름차순.
fn intersectNodeSorter(ctx: void, a: IntersectNode, b: IntersectNode) bool {
    _ = ctx;
    if (@abs(a.pt.y - b.pt.y) < Eps) {
        return a.pt.x < b.pt.x;
    }
    return a.pt.y > b.pt.y; // Y 내림차순
}

/// 교차점 목록 빌드 (merge sort). 교차점이 있으면 true 반환.
fn buildIntersectList(cb: *ClipperBase, top_y: f64, allocator: std.mem.Allocator) !bool {
    if (cb.actives == null or cb.actives.?.next_in_ael == null) {
        return false;
    }
    adjustCurrXAndCopyToSEL(cb, top_y);

    var left = cb.sel;
    while (left) |l| {
        if (l.jump == null) break; // Odin: for left != nil && left.jump != nil
        var prev_base: ?*Active = null;
        while (l) |curr_left| : (l = curr_left.jump orelse break) {
            if (curr_left.jump == null) break;

            const curr_base = curr_left;
            var right = curr_left.jump.?;
            var l_end = right;
            const r_end = right.next_in_sel orelse break;

            curr_left.jump = r_end;

            while (curr_left != l_end and right != r_end) {
                if (right.curr_x < curr_left.curr_x) {
                    // intersections found — record all edges between curr_left and right
                    var tmp = right.prev_in_sel orelse break;
                    while (true) {
                        try addNewIntersectNode(cb, tmp, right, top_y, allocator);
                        if (tmp == curr_left) break;
                        tmp = tmp.prev_in_sel orelse break;
                    }
                    tmp = right;
                    right = extractFromSEL(tmp) orelse break;
                    l_end = right;
                    insert1Before2InSEL(tmp, curr_left);

                    if (curr_left == curr_base) {
                        curr_base = tmp;
                        curr_base.jump = r_end;
                        if (prev_base == null) {
                            cb.sel = curr_base;
                        } else {
                            prev_base.?.jump = curr_base;
                        }
                    }
                } else {
                    curr_left = curr_left.next_in_sel orelse break;
                }
            }
            prev_base = curr_base;
            curr_left = r_end; // Odin: left = r_end — 다음 쌍으로 전진
        }
        left = cb.sel;
    }
    return cb.intersect_nodes.items.len > 0;
}

/// AEL에서 인접한 엣지인지 확인.
fn edgesAdjacentInAEL(node: IntersectNode) bool {
    return node.edge1.?.next_in_ael == node.edge2 or
        node.edge1.?.prev_in_ael == node.edge2;
}

/// 교차점 목록 처리 (정렬 + 교차점 적용).
fn processIntersectList(cb: *ClipperBase, allocator: std.mem.Allocator) !void {
    if (cb.intersect_nodes.items.len == 0) return;

    // 정렬: Y 내림차순, X 오름차순
    std.mem.sort(IntersectNode, cb.intersect_nodes.items, {}, intersectNodeSorter);

    var i: usize = 0;
    while (i < cb.intersect_nodes.items.len) : (i += 1) {
        const node = &cb.intersect_nodes.items[i];
        if (!edgesAdjacentInAEL(node.*)) {
            // 뒤에서 인접한 노드 찾아서 스왑
            var j = i + 1;
            while (j < cb.intersect_nodes.items.len and !edgesAdjacentInAEL(cb.intersect_nodes.items[j])) {
                j += 1;
            }
            if (j < cb.intersect_nodes.items.len) {
                const tmp = cb.intersect_nodes.items[i];
                cb.intersect_nodes.items[i] = cb.intersect_nodes.items[j];
                cb.intersect_nodes.items[j] = tmp;
            }
        }

        const node_ref = &cb.intersect_nodes.items[i];
        const ip: Point = .{
            .x = node_ref.pt.x,
            .y = node_ref.pt.y,
        };
        intersectEdges(cb, node_ref.edge1, node_ref.edge2, ip, allocator);
        swapPositionsInAEL(cb, node_ref.edge1.?, node_ref.edge2.?);
        node_ref.edge1.?.curr_x = node_ref.pt.x;
        node_ref.edge2.?.curr_x = node_ref.pt.x;
        checkJoinLeft(cb, node_ref.edge2, ip, true, allocator);
        checkJoinRight(cb, node_ref.edge1, ip, true, allocator);
    }
}

/// 교차점 처리 실행.
fn doIntersections(cb: *ClipperBase, top_y: f64, allocator: std.mem.Allocator) !void {
    if (try buildIntersectList(cb, top_y, allocator)) {
        try processIntersectList(cb, allocator);
        cb.intersect_nodes.clearRetainingCapacity();
    }
}

// ──── Top of scanbeam processing ──────────────────────────────────────────────

/// 스캔빔 상단 처리.
fn doTopOfScanbeam(cb: *ClipperBase, y: f64, allocator: std.mem.Allocator) void {
    cb.sel = null; // sel_ reused for horizontals
    var e = cb.actives;
    while (e) |active| {
        if (@abs(active.top.y - y) < Eps) {
            active.curr_x = active.top.x;
            if (isMaximaE(active)) {
                e = doMaxima(cb, active, allocator);
                continue;
            } else {
                if (isHotEdge(active)) {
                    _ = addOutPt(cb, active, active.top, allocator);
                }
                updateEdgeIntoAEL(cb, active, allocator);
                if (isHorizontalE(active)) {
                    pushHorz(cb, active);
                }
            }
        } else {
            active.curr_x = topX(active.dx, active.bot, active.top, y);
        }
        e = active.next_in_ael;
    }
}

/// 최대점 처리 및 AEL에서 제거.
fn doMaxima(cb: *ClipperBase, e: *Active, allocator: std.mem.Allocator) ?*Active {
    const prev_e = e.prev_in_ael;
    const next_e = e.next_in_ael;

    if (isOpenEndE(e)) {
        if (isHotEdge(e)) {
            _ = addOutPt(cb, e, e.top, allocator);
        }
        if (!isHorizontalE(e)) {
            if (isHotEdge(e)) {
                if (isFront(e)) {
                    e.outrec.?.front_edge = null;
                } else {
                    e.outrec.?.back_edge = null;
                }
                e.outrec = null;
            }
            deleteFromAEL(cb, e);
        }
        return next_e;
    }

    const max_pair = getMaximaPair(e);
    if (max_pair == null) return next_e;

    if (isJoined(e)) split(cb, e, e.top, allocator);
    if (isJoined(max_pair)) split(cb, max_pair, max_pair.?.top, allocator);

    var next_e2 = next_e;
    while (next_e2 != max_pair) {
        intersectEdges(cb, e, next_e2, e.top, allocator);
        swapPositionsInAEL(cb, e, next_e2);
        next_e2 = e.next_in_ael orelse break;
    }

    if (isOpen(e)) {
        if (isHotEdge(e)) {
            _ = addLocalMaxPoly(cb, e, max_pair, e.top, allocator);
        }
        deleteFromAEL(cb, max_pair);
        deleteFromAEL(cb, e);
        if (prev_e) |pe| {
            return pe.next_in_ael;
        }
        return cb.actives;
    }

    if (isHotEdge(e)) {
        _ = addLocalMaxPoly(cb, e, max_pair, e.top, allocator);
    }
    deleteFromAEL(cb, e);
    deleteFromAEL(cb, max_pair);
    if (prev_e) |pe| {
        return pe.next_in_ael;
    }
    return cb.actives;
}

/// AEL 엣지 업데이트 (vertex_top推进).
fn updateEdgeIntoAEL(cb: *ClipperBase, e: *Active, allocator: std.mem.Allocator) void {
    e.bot = e.top;
    e.vertex_top = nextVertex(e) orelse return;
    e.top = e.vertex_top.?.pt;
    e.curr_x = e.bot.x;
    setDx(e);

    if (isJoined(e)) split(cb, e, e.bot, allocator);

    if (isHorizontalE(e)) {
        if (!isOpen(e)) trimHorz(e, cb.preserve_collinear);
        return;
    }
    insertScanline(cb, e.top.y, allocator);
    checkJoinLeft(cb, e, e.bot, false, allocator);
    checkJoinRight(cb, e, e.bot, true, allocator);
}

/// 수평 엣지 트리밍 (연속 수평 엣지 병합).
fn trimHorz(e: *Active, preserveCollinear: bool) void {
    while (true) {
        const pt = nextVertex(e).?.pt;
        if (@abs(pt.y - e.top.y) > Eps) break;
        if (preserveCollinear and ((pt.x < e.top.x) != (e.bot.x < e.top.x))) break;
        e.vertex_top = nextVertex(e);
        e.top = pt;
        if (isMaximaE(e)) break;
    }
    setDx(e);
}

/// 최대점 쌍 찾기.
fn getMaximaPair(e: *Active) ?*Active {
    var e2 = e.next_in_ael;
    while (e2) |ae2| {
        if (ae2.vertex_top == e.vertex_top) return ae2;
        e2 = ae2.next_in_ael;
    }
    return null;
}

/// 현재 Y 최대점 꼭짓점 찾기 (닫힌 경로).
fn getCurrYMaximaVertex(e: *Active) ?*Vertex {
    var result = e.vertex_top orelse return null;
    if (e.wind_dx > 0) {
        while (result.next) |n| {
            if (@abs(n.pt.y - result.pt.y) > Eps) break;
            result = n;
        }
    } else {
        while (result.prev) |p| {
            if (@abs(p.pt.y - result.pt.y) > Eps) break;
            result = p;
        }
    }
    if (!isMaximaV(result)) return null;
    return result;
}

/// 현재 Y 최대점 꼭짓점 찾기 (열린 경로).
fn getCurrYMaximaVertexOpen(e: *Active) ?*Vertex {
    var result = e.vertex_top orelse return null;
    if (e.wind_dx > 0) {
        while (result.next) |n| {
            if (@abs(n.pt.y - result.pt.y) > Eps) break;
            if (hasFlag(n, .OpenEnd) or hasFlag(n, .LocalMax)) break;
            result = n;
        }
    } else {
        while (result.prev) |p| {
            if (@abs(p.pt.y - result.pt.y) > Eps) break;
            if (hasFlag(p, .OpenEnd) or hasFlag(p, .LocalMax)) break;
            result = p;
        }
    }
    if (!isMaximaV(result)) return null;
    return result;
}

/// 수평 방향 리셋. 왼쪽→오른쪽이면 true 반환.
fn resetHorzDirection(horz: *Active, max_vertex: *Vertex, horz_left: *f64, horz_right: *f64) bool {
    if (@abs(horz.bot.x - horz.top.x) < Eps) {
        horz_left.* = horz.curr_x;
        horz_right.* = horz.curr_x;
        var e = horz.next_in_ael;
        while (e) |ae| {
            if (ae.vertex_top == max_vertex) break;
            e = ae.next_in_ael;
        }
        return e != null;
    } else if (horz.curr_x < horz.top.x) {
        horz_left.* = horz.curr_x;
        horz_right.* = horz.top.x;
        return true;
    } else {
        horz_left.* = horz.top.x;
        horz_right.* = horz.curr_x;
        return false;
    }
}

/// 마지막 출력 점 반환.
fn getLastOp(hot_edge: *Active) ?*OutPt {
    const outrec = hot_edge.outrec orelse return null;
    var result = outrec.pts;
    if (!isFront(hot_edge)) {
        result = result.?.next;
    }
    return result;
}

// ──── DoHorizontal (core horizontal edge processing) ─────────────────────────

/// 수평 조인 시도 추가.
fn addTrialHorzJoin(cb: *ClipperBase, op: *OutPt, allocator: std.mem.Allocator) void {
    if (op.outrec.?.is_open) return;
    cb.horz_seg_list.append(allocator, .{
        .left_op = op,
        .right_op = null,
        .left_to_right = true,
    }) catch {};
}

/// 수평 엣지 처리 (핵심).
fn doHorizontal(cb: *ClipperBase, horz: *Active, allocator: std.mem.Allocator) void {
    const horzIsOpen = isOpen(horz);
    const y = horz.bot.y;

    const vertex_max = if (horzIsOpen)
        getCurrYMaximaVertexOpen(horz) orelse return
    else
        getCurrYMaximaVertex(horz) orelse return;

    var horz_left: f64 = 0;
    var horz_right: f64 = 0;
    var is_left_to_right = resetHorzDirection(horz, vertex_max, &horz_left, &horz_right);

    if (isHotEdge(horz)) {
        const pt: Point = .{
            .x = horz.curr_x,
            .y = y,
        };
        const op = addOutPt(cb, horz, pt, allocator) orelse return;
        addTrialHorzJoin(cb, op, allocator);
    }

    while (true) {
        var e = if (is_left_to_right) horz.next_in_ael else horz.prev_in_ael;

        while (e) |ae| {
            if (ae.vertex_top == vertex_max) {
                if (isHotEdge(horz) and isJoined(ae)) {
                    split(cb, ae, ae.top, allocator);
                }
                if (isHotEdge(horz)) {
                    while (horz.vertex_top != vertex_max) {
                        _ = addOutPt(cb, horz, horz.top, allocator);
                        updateEdgeIntoAEL(cb, horz, allocator);
                    }
                    if (is_left_to_right) {
                        _ = addLocalMaxPoly(cb, horz, ae, horz.top, allocator);
                    } else {
                        _ = addLocalMaxPoly(cb, ae, horz, horz.top, allocator);
                    }
                }
                deleteFromAEL(cb, ae);
                deleteFromAEL(cb, horz);
                return;
            }

            if (vertex_max != horz.vertex_top or isOpenEndE(horz)) {
                if ((is_left_to_right and ae.curr_x > horz_right) or
                    (!is_left_to_right and ae.curr_x < horz_left))
                {
                    break;
                }

                if (@abs(ae.curr_x - horz.top.x) < Eps and !isHorizontalE(ae)) {
                    const pt = nextVertex(horz).?.pt;
                    if (is_left_to_right) {
                        if (isOpen(ae) and !isSamePolyType(ae, horz) and !isHotEdge(ae)) {
                            if (topX(ae.dx, ae.bot, ae.top, pt.y) > pt.x) break;
                        } else if (topX(ae.dx, ae.bot, ae.top, pt.y) >= pt.x) break;
                    } else {
                        if (isOpen(ae) and !isSamePolyType(ae, horz) and !isHotEdge(ae)) {
                            if (topX(ae.dx, ae.bot, ae.top, pt.y) < pt.x) break;
                        } else if (topX(ae.dx, ae.bot, ae.top, pt.y) <= pt.x) break;
                    }
                }
            }

            const pt: Point = .{
                .x = ae.curr_x,
                .y = horz.bot.y,
            };
            if (is_left_to_right) {
                intersectEdges(cb, horz, ae, pt, allocator);
                swapPositionsInAEL(cb, horz, ae);
                checkJoinLeft(cb, ae, pt, false, allocator);
                horz.curr_x = ae.curr_x;
                e = horz.next_in_ael;
            } else {
                intersectEdges(cb, ae, horz, pt, allocator);
                swapPositionsInAEL(cb, ae, horz);
                checkJoinRight(cb, ae, pt, false, allocator);
                horz.curr_x = ae.curr_x;
                e = horz.prev_in_ael;
            }

            if (horz.outrec) |hrz_outrec| {
                _ = hrz_outrec;
                if (getLastOp(horz)) |op| {
                    addTrialHorzJoin(cb, op, allocator);
                }
            }
        }

        // check if finished with consecutive horizontals
        if (horzIsOpen and isOpenEndE(horz)) {
            if (isHotEdge(horz)) {
                _ = addOutPt(cb, horz, horz.top, allocator);
                if (isFront(horz)) {
                    horz.outrec.?.front_edge = null;
                } else {
                    horz.outrec.?.back_edge = null;
                }
                horz.outrec = null;
            }
            deleteFromAEL(cb, horz);
            return;
        } else if (@abs(nextVertex(horz).?.pt.y - horz.top.y) > Eps) {
            break;
        }

        // more horizontals in bound
        if (isHotEdge(horz)) {
            _ = addOutPt(cb, horz, horz.top, allocator);
        }
        updateEdgeIntoAEL(cb, horz, allocator);
        is_left_to_right = resetHorzDirection(horz, vertex_max, &horz_left, &horz_right);
    }

    if (isHotEdge(horz)) {
        if (addOutPt(cb, horz, horz.top, allocator)) |op| {
            addTrialHorzJoin(cb, op, allocator);
        }
    }
    updateEdgeIntoAEL(cb, horz, allocator);
}

// ──── ExecuteInternal (main scanline loop) + output assembly ─────────────────

/// 내부 실행 (메인 루프).
fn executeInternal(cb: *ClipperBase, ct: ClipType, fr: FillRule, allocator: std.mem.Allocator) !bool {
    cb.cliptype = ct;
    cb.fillrule = fr;
    cb.using_polytree = false;
    reset(cb, allocator);

    var y: f64 = 0;
    if (ct == .NoClip or !popScanline(cb, &y)) {
        return true;
    }

    while (cb.succeeded) {
        insertLocalMinimaIntoAEL(cb, y, allocator);

        var e: ?*Active = null;
        while (popHorz(cb, &e)) {
            doHorizontal(cb, e.?, allocator);
        }

        if (cb.horz_seg_list.items.len > 0) {
            // _convertHorzSegsToJoins(cb)  (deferred — not critical for basic ops)
            cb.horz_seg_list.clearRetainingCapacity();
        }

        cb.bot_y = y;
        if (!popScanline(cb, &y)) break;

        try doIntersections(cb, y, allocator);
        doTopOfScanbeam(cb, y, allocator);

        e = null;
        while (popHorz(cb, &e)) {
            doHorizontal(cb, e.?, allocator);
        }
    }

    // if cb.succeeded_ { _processHorzJoins(cb) }  (deferred)
    return cb.succeeded;
}

// ============================================================================
// Stage 5: Fast RectClip Implementation
// Odin clipper.odin lines 2545~3242 포팅
// ============================================================================

// ──── RectClip Internal Utilities ────────────────────────────────────────────

/// 점이 사각형 경계의 어느 위치에 있는지 반환. 경계 위에 있으면 false (방향 모호), 내부이면 true.
fn rectClipGetLocation(rec: RectF64, pt: Point, loc: *Location) bool {
    if (pt.x == rec.left and pt.y >= rec.top and pt.y <= rec.bottom) {
        loc.* = .Left;
        return false;
    } else if (pt.x == rec.right and pt.y >= rec.top and pt.y <= rec.bottom) {
        loc.* = .Right;
        return false;
    } else if (pt.y == rec.top and pt.x >= rec.left and pt.x <= rec.right) {
        loc.* = .Top;
        return false;
    } else if (pt.y == rec.bottom and pt.x >= rec.left and pt.x <= rec.right) {
        loc.* = .Bottom;
        return false;
    } else if (pt.x < rec.left) {
        loc.* = .Left;
    } else if (pt.x > rec.right) {
        loc.* = .Right;
    } else if (pt.y < rec.top) {
        loc.* = .Top;
    } else if (pt.y > rec.bottom) {
        loc.* = .Bottom;
    } else {
        loc.* = .Inside;
    }
    return true;
}

/// 두 선분(p1-p2, p3-p4)의 교차점을 ip에 저장. 유효한 교차점이 있으면 true.
fn rectClipGetSegmentIntersection(p1: Point, p2: Point, p3: Point, p4: Point, ip: *Point) bool {
    const res1 = crossProductSign(p1, p3, p4);
    const res2 = crossProductSign(p2, p3, p4);
    if (res1 == 0) {
        ip.* = p1;
        if (res2 == 0) return false;
        if (p1.x == p3.x and p1.y == p3.y) return true;
        if (p1.x == p4.x and p1.y == p4.y) return true;
        if (p3.y == p4.y) return (p1.x > p3.x) == (p1.x < p4.x);
        return (p1.y > p3.y) == (p1.y < p4.y);
    } else if (res2 == 0) {
        ip.* = p2;
        if (p2.x == p3.x and p2.y == p3.y) return true;
        if (p2.x == p4.x and p2.y == p4.y) return true;
        if (p3.y == p4.y) return (p2.x > p3.x) == (p2.x < p4.x);
        return (p2.y > p3.y) == (p2.y < p4.y);
    }
    if ((res1 > 0) == (res2 > 0)) return false;
    const res3 = crossProductSign(p3, p1, p2);
    const res4 = crossProductSign(p4, p1, p2);
    if (res3 == 0) {
        ip.* = p3;
        if (p3.x == p1.x and p3.y == p1.y) return true;
        if (p3.x == p2.x and p3.y == p2.y) return true;
        if (p1.y == p2.y) return (p3.x > p1.x) == (p3.x < p2.x);
        return (p3.y > p1.y) == (p3.y < p2.y);
    } else if (res4 == 0) {
        ip.* = p4;
        if (p4.x == p1.x and p4.y == p1.y) return true;
        if (p4.x == p2.x and p4.y == p2.y) return true;
        if (p1.y == p2.y) return (p4.x > p1.x) == (p4.x < p2.x);
        return (p4.y > p1.y) == (p4.y < p2.y);
    }
    if ((res3 > 0) == (res4 > 0)) return false;
    return getLineIntersectPt(p1, p2, p3, p4, ip);
}

/// 시계 방향이면 다음 모서리, 반시계 방향이면 이전 모서리 반환.
fn rectClipGetAdjacent(loc: Location, isClockwise: bool) Location {
    const d: i32 = if (isClockwise) @as(i32, 1) else @as(i32, 3);
    return @enumFromInt(@rem((@intFromEnum(loc) + d), 4));
}

/// prev에서 curr로 이동이 시계 방향인지.
fn rectClipHeadingClockwise(prev: Location, curr: Location) bool {
    return (@intFromEnum(prev) + 1) % 4 == @intFromEnum(curr);
}

/// 두 Location이 반대 방향인지 (차이가 2).
fn rectClipAreOpposites(prev: Location, curr: Location) bool {
    return @abs(@as(i32, @intFromEnum(prev)) - @as(i32, @intFromEnum(curr))) == 2;
}

/// prev에서 curr로 이동이 시계 방향인지 (반대 방향일 경우 rect_mp 기준 교차곱으로 판단).
fn rectClipIsClockwise(prev: Location, curr: Location, prev_pt: Point, curr_pt: Point, rect_mp: Point) bool {
    if (rectClipAreOpposites(prev, curr)) {
        return crossProductSign(prev_pt, rect_mp, curr_pt) < 0;
    }
    return rectClipHeadingClockwise(prev, curr);
}

/// 결과 리스트에 점 추가. start_new가 true이면 새 체인 시작.
fn rectClipAdd(rc: *RectClip64, pt: Point, start_new: bool, allocator: std.mem.Allocator) ?*OutPt2 {
    var curr_idx = rc.results.items.len;
    if (curr_idx == 0 or start_new) {
        const result = allocator.create(OutPt2) catch return null;
        result.pt = pt;
        result.owner_idx = curr_idx;
        result.edge = null;
        result.next = result;
        result.prev = result;
        rc.results.append(allocator, result) catch {
            allocator.destroy(result);
            return null;
        };
        return result;
    }
    curr_idx -= 1;
    const prevOp = rc.results.items[curr_idx] orelse return null;
    if (prevOp.pt.x == pt.x and prevOp.pt.y == pt.y) return prevOp;
    const result = allocator.create(OutPt2) catch return null;
    result.owner_idx = curr_idx;
    result.pt = pt;
    result.edge = null;
    result.next = prevOp.next;
    prevOp.next.?.prev = result;
    prevOp.next = result;
    result.prev = prevOp;
    rc.results.items[curr_idx] = result;
    return result;
}

/// 시계 방향 코너 추가.
fn rectClipAddCorner1(rc: *RectClip64, prev: Location, curr: Location, allocator: std.mem.Allocator) void {
    if (rectClipHeadingClockwise(prev, curr)) {
        _ = rectClipAdd(rc, rc.rect_as_path[@intFromEnum(prev)], false, allocator);
    } else {
        _ = rectClipAdd(rc, rc.rect_as_path[@intFromEnum(curr)], false, allocator);
    }
}

/// 코너 추가 후 loc 업데이트.
fn rectClipAddCorner2(rc: *RectClip64, loc: *Location, isClockwise: bool, allocator: std.mem.Allocator) void {
    if (isClockwise) {
        _ = rectClipAdd(rc, rc.rect_as_path[@intFromEnum(loc.*)], false, allocator);
        loc.* = rectClipGetAdjacent(loc.*, true);
    } else {
        loc.* = rectClipGetAdjacent(loc.*, false);
        _ = rectClipAdd(rc, rc.rect_as_path[@intFromEnum(loc.*)], false, allocator);
    }
}

/// 현재 Location에서 다은 Location으로 전진 (경로 따라).
fn rectClipGetNextLocation(rc: *RectClip64, path: []const Point, loc: *Location, i: *usize, highI: usize, allocator: std.mem.Allocator) void {
    switch (loc.*) {
        .Left => {
            while (i.* <= highI and path[i.*].x <= rc.rect.left) {
                i.* += 1;
            }
            if (i.* > highI) return;
            if (path[i.*].x >= rc.rect.right) {
                loc.* = .Right;
            } else if (path[i.*].y <= rc.rect.top) {
                loc.* = .Top;
            } else if (path[i.*].y >= rc.rect.bottom) {
                loc.* = .Bottom;
            } else {
                loc.* = .Inside;
            }
        },
        .Bottom => {
            while (i.* <= highI and path[i.*].y >= rc.rect.bottom) {
                i.* += 1;
            }
            if (i.* > highI) return;
            if (path[i.*].y <= rc.rect.top) {
                loc.* = .Top;
            } else if (path[i.*].x <= rc.rect.left) {
                loc.* = .Left;
            } else if (path[i.*].x >= rc.rect.right) {
                loc.* = .Right;
            } else {
                loc.* = .Inside;
            }
        },
        .Top => {
            while (i.* <= highI and path[i.*].y <= rc.rect.top) {
                i.* += 1;
            }
            if (i.* > highI) return;
            if (path[i.*].y >= rc.rect.bottom) {
                loc.* = .Bottom;
            } else if (path[i.*].x <= rc.rect.left) {
                loc.* = .Left;
            } else if (path[i.*].x >= rc.rect.right) {
                loc.* = .Right;
            } else {
                loc.* = .Inside;
            }
        },
        .Right => {
            while (i.* <= highI and path[i.*].x >= rc.rect.right) {
                i.* += 1;
            }
            if (i.* > highI) return;
            if (path[i.*].x <= rc.rect.left) {
                loc.* = .Left;
            } else if (path[i.*].y <= rc.rect.top) {
                loc.* = .Top;
            } else if (path[i.*].y >= rc.rect.bottom) {
                loc.* = .Bottom;
            } else {
                loc.* = .Inside;
            }
        },
        .Inside => {
            while (i.* <= highI) {
                if (path[i.*].x < rc.rect.left) {
                    loc.* = .Left;
                } else if (path[i.*].x > rc.rect.right) {
                    loc.* = .Right;
                } else if (path[i.*].y > rc.rect.bottom) {
                    loc.* = .Bottom;
                } else if (path[i.*].y < rc.rect.top) {
                    loc.* = .Top;
                } else {
                    _ = rectClipAdd(rc, path[i.*], false, allocator);
                    i.* += 1;
                    continue;
                }
                break;
            }
        },
    }
}

/// start_locs가 시계 방향 순서인지.
fn rectClipStartLocsAreClockwise(startlocs: []const Location) bool {
    var result: i32 = 0;
    var i: usize = 1;
    while (i < startlocs.len) : (i += 1) {
        const d = @as(i32, @intFromEnum(startlocs[i])) - @as(i32, @intFromEnum(startlocs[i - 1]));
        switch (d) {
            -1 => result -= 1,
            1 => result += 1,
            -3 => result += 1,
            3 => result -= 1,
            else => {},
        }
    }
    return result > 0;
}

/// 현재 loc에서 p→p2가 사각형 경계와 만나는 교차점 계산.
fn rectClipGetIntersection(rc: *RectClip64, p: Point, p2: Point, loc: *Location, ip: *Point) bool {
    const rp = rc.rect_as_path;
    switch (loc.*) {
        .Left => {
            if (rectClipGetSegmentIntersection(p, p2, rp[0], rp[3], ip)) return true;
            if (p.y < rp[0].y and rectClipGetSegmentIntersection(p, p2, rp[0], rp[1], ip)) {
                loc.* = .Top;
                return true;
            }
            if (rectClipGetSegmentIntersection(p, p2, rp[2], rp[3], ip)) {
                loc.* = .Bottom;
                return true;
            }
        },
        .Top => {
            if (rectClipGetSegmentIntersection(p, p2, rp[0], rp[1], ip)) return true;
            if (p.x < rp[0].x and rectClipGetSegmentIntersection(p, p2, rp[0], rp[3], ip)) {
                loc.* = .Left;
                return true;
            }
            if (rectClipGetSegmentIntersection(p, p2, rp[1], rp[2], ip)) {
                loc.* = .Right;
                return true;
            }
        },
        .Right => {
            if (rectClipGetSegmentIntersection(p, p2, rp[1], rp[2], ip)) return true;
            if (p.y < rp[1].y and rectClipGetSegmentIntersection(p, p2, rp[0], rp[1], ip)) {
                loc.* = .Top;
                return true;
            }
            if (rectClipGetSegmentIntersection(p, p2, rp[2], rp[3], ip)) {
                loc.* = .Bottom;
                return true;
            }
        },
        .Bottom => {
            if (rectClipGetSegmentIntersection(p, p2, rp[2], rp[3], ip)) return true;
            if (p.x < rp[3].x and rectClipGetSegmentIntersection(p, p2, rp[0], rp[3], ip)) {
                loc.* = .Left;
                return true;
            }
            if (rectClipGetSegmentIntersection(p, p2, rp[1], rp[2], ip)) {
                loc.* = .Right;
                return true;
            }
        },
        .Inside => {
            if (rectClipGetSegmentIntersection(p, p2, rp[0], rp[3], ip)) {
                loc.* = .Left;
                return true;
            }
            if (rectClipGetSegmentIntersection(p, p2, rp[0], rp[1], ip)) {
                loc.* = .Top;
                return true;
            }
            if (rectClipGetSegmentIntersection(p, p2, rp[1], rp[2], ip)) {
                loc.* = .Right;
                return true;
            }
            if (rectClipGetSegmentIntersection(p, p2, rp[2], rp[3], ip)) {
                loc.* = .Bottom;
                return true;
            }
        },
    }
    return false;
}

// ──── RectClip Contains / Point-in-Polygon ────────────────────────────────────

/// 사각형이 경로에 완전히 포함되는지.
fn rectClipContainsRect(path: []const Point, rec: RectF64) bool {
    if (path.len == 0) return false;
    var xmin = path[0].x;
    var ymin = path[0].y;
    var xmax = path[0].x;
    var ymax = path[0].y;
    for (path) |pt| {
        if (pt.x < xmin) xmin = pt.x;
        if (pt.x > xmax) xmax = pt.x;
        if (pt.y < ymin) ymin = pt.y;
        if (pt.y > ymax) ymax = pt.y;
    }
    return xmin <= rec.left and xmax >= rec.right and ymin <= rec.top and ymax >= rec.bottom;
}

/// path1이 path2를 포함하는지 (point-in-polygon 기반).
fn rectClipPath1ContainsPath2(path1: []const Point, path2: []const Point) bool {
    var io_count: i32 = 0;
    for (path2) |pt| {
        const loc2 = pointInPolygon2D(pt, path1);
        switch (loc2) {
            1 => io_count -= 1,
            -1 => io_count += 1,
            else => {},
        }
        if (@abs(io_count) > 1) break;
    }
    return io_count <= 0;
}

/// 2D 점이 폴리곤 내부에 있는지. 0: 경계 위, -1: 외부, 1: 내부.
fn pointInPolygon2D(pt: Point, polygon: []const Point) i32 {
    if (polygon.len < 3) return -1;
    var val: i32 = 0;
    var first: usize = 0;
    while (first < polygon.len and polygon[first].y == pt.y) : (first += 1) {}
    if (first == polygon.len) return -1;
    var is_above = polygon[first].y < pt.y;
    const starting_above = is_above;
    var curr: usize = first + 1;
    while (true) {
        if (curr == polygon.len) {
            curr = 0;
        }
        if (curr == first) break;
        if (is_above) {
            while (polygon[curr].y < pt.y) {
                curr += 1;
                if (curr == polygon.len) curr = 0;
                if (curr == first) break;
            }
        } else {
            while (polygon[curr].y > pt.y) {
                curr += 1;
                if (curr == polygon.len) curr = 0;
                if (curr == first) break;
            }
        }
        if (curr == first) break;
        if (polygon[curr].y == pt.y) {
            if (polygon[curr].x == pt.x) return 0;
            curr += 1;
            if (curr == first) break;
            continue;
        }
        const prev_idx: usize = if (curr > 0) curr -% 1 else polygon.len - 1;
        if (pt.x < polygon[curr].x and pt.x < polygon[prev_idx].x) {
            // do nothing
        } else if (pt.x > polygon[prev_idx].x and pt.x > polygon[curr].x) {
            val = 1 - val;
        } else {
            const cp = crossProductSign(polygon[prev_idx], polygon[curr], pt);
            if (cp == 0) return 0;
            if ((cp < 0) == is_above) val = 1 - val;
        }
        is_above = !is_above;
        curr += 1;
        if (curr == polygon.len) curr = 0;
    }
    if (is_above != starting_above) {
        const prev_idx: usize = if (curr > 0) curr -% 1 else polygon.len - 1;
        const cp = crossProductSign(polygon[prev_idx], polygon[curr], pt);
        if (cp == 0) return 0;
        if ((cp < 0) == is_above) val = 1 - val;
    }
    return if (val == 0) @as(i32, -1) else @as(i32, 1);
}

// ──── RectClip Execute Internal ──────────────────────────────────────────────

/// 단일 경로에 대한 RectClip 실행.
fn rectClipExecuteInternal(rc: *RectClip64, path: []const Point, allocator: std.mem.Allocator) void {
    if (path.len < 1) return;
    const highI = path.len - 1;
    var prev: Location = .Inside;
    var loc: Location = .Inside;
    var crossing_loc: Location = .Inside;
    var first_cross: Location = .Inside;

    if (!rectClipGetLocation(rc.rect, path[highI], &loc)) {
        var ii2: usize = highI;
        while (ii2 > 0 and !rectClipGetLocation(rc.rect, path[ii2 - 1], &prev)) {
            ii2 -= 1;
        }
        if (ii2 == 0) {
            for (path) |pt| {
                _ = rectClipAdd(rc, pt, false, allocator);
            }
            return;
        }
        if (prev == .Inside) loc = .Inside;
    }
    const starting_loc = loc;

    var i: usize = 0;
    while (i <= highI) {
        prev = loc;
        const crossing_prev = crossing_loc;
        rectClipGetNextLocation(rc, path, &loc, &i, highI, allocator);
        if (i > highI) break;

        const prev_pt: Point = if (i > 0) path[i - 1] else path[highI];
        crossing_loc = loc;

        var ip: Point = .{ .x = 0, .y = 0 };
        var ip2: Point = .{ .x = 0, .y = 0 };

        if (!rectClipGetIntersection(rc, path[i], prev_pt, &crossing_loc, &ip)) {
            if (crossing_prev == .Inside) {
                const isClockw = rectClipIsClockwise(prev, loc, prev_pt, path[i], rc.rect_mp);
                while (true) {
                    rc.start_locs.append(allocator, prev) catch return;
                    prev = rectClipGetAdjacent(prev, isClockw);
                    if (prev == loc) break;
                }
                crossing_loc = crossing_prev;
            } else if (prev != .Inside and prev != loc) {
                const isClockw = rectClipIsClockwise(prev, loc, prev_pt, path[i], rc.rect_mp);
                while (true) {
                    rectClipAddCorner2(rc, &prev, isClockw, allocator);
                    if (prev == loc) break;
                }
            }
            i += 1;
            continue;
        }

        // 교차: 사각형 경계를 가로지름
        if (loc == .Inside) {
            // entering
            if (first_cross == .Inside) {
                first_cross = crossing_loc;
                rc.start_locs.append(allocator, prev) catch return;
            } else if (prev != crossing_loc) {
                const isClockw = rectClipIsClockwise(prev, crossing_loc, prev_pt, path[i], rc.rect_mp);
                while (true) {
                    rectClipAddCorner2(rc, &prev, isClockw, allocator);
                    if (prev == crossing_loc) break;
                }
            }
        } else if (prev != .Inside) {
            // passing through — 두 교차점 모두 필요
            loc = prev;
            _ = rectClipGetIntersection(rc, prev_pt, path[i], &loc, &ip2);
            if (crossing_prev != .Inside and crossing_prev != loc) {
                rectClipAddCorner1(rc, crossing_prev, loc, allocator);
            }
            if (first_cross == .Inside) {
                first_cross = loc;
                rc.start_locs.append(allocator, prev) catch return;
            }
            loc = crossing_loc;
            _ = rectClipAdd(rc, ip2, false, allocator);
            if (ip.x == ip2.x and ip.y == ip2.y) {
                _ = rectClipGetLocation(rc.rect, path[i], &loc);
                rectClipAddCorner1(rc, crossing_loc, loc, allocator);
                crossing_loc = loc;
                continue;
            }
        } else {
            // exiting
            loc = crossing_loc;
            if (first_cross == .Inside) {
                first_cross = crossing_loc;
            }
        }
        _ = rectClipAdd(rc, ip, false, allocator);
    }

    if (first_cross == .Inside) {
        if (starting_loc != .Inside) {
            if (rectClipContainsRect(path, rc.rect) and rectClipPath1ContainsPath2(path, rc.rect_as_path[0..4])) {
                const isClockwisePath = rectClipStartLocsAreClockwise(rc.start_locs.items);
                var j: usize = 0;
                while (j < 4) : (j += 1) {
                    const k: usize = if (isClockwisePath) j else 3 - j;
                    _ = rectClipAdd(rc, rc.rect_as_path[k], false, allocator);
                }
            }
        }
    } else if (loc != .Inside and (loc != first_cross or rc.start_locs.items.len > 2)) {
        if (rc.start_locs.items.len > 0) {
            prev = loc;
            for (rc.start_locs.items) |loc2| {
                if (prev == loc2) continue;
                rectClipAddCorner2(rc, &prev, rectClipHeadingClockwise(prev, loc2), allocator);
                prev = loc2;
            }
            loc = prev;
        }
        if (loc != first_cross) {
            rectClipAddCorner2(rc, &loc, rectClipHeadingClockwise(loc, first_cross), allocator);
        }
    }
}

// ──── RectClip Execute (paths) ───────────────────────────────────────────────

/// 여러 경로에 대해 RectClip 실행. 결과는 temp allocator로 할당된 Point 슬라이스 목록.
fn rectClipExecute(rc: *RectClip64, paths: []const []const Point, allocator: std.mem.Allocator) ![][]Point {
    var result = std.ArrayList([]Point).empty;
    for (paths) |path| {
        if (path.len < 3) continue;
        rectClipExecuteInternal(rc, path, allocator);
        rectClipCheckEdges(rc, allocator);
        var edgeIdx: usize = 0;
        while (edgeIdx < 4) : (edgeIdx += 1) {
            rectClipTidyEdges(rc, edgeIdx, &rc.edges[edgeIdx * 2], &rc.edges[edgeIdx * 2 + 1], allocator);
        }
        for (0..rc.results.items.len) |res_idx| {
            var op = rc.results.items[res_idx];
            const tmp = rectClipGetPath(&op, allocator);
            if (tmp.len > 0) {
                try result.append(allocator, tmp);
            }
        }
        // 경로별 초기화
        rc.results.clearRetainingCapacity();
        for (0..8) |j| {
            rc.edges[j].clearRetainingCapacity();
        }
        rc.start_locs.clearRetainingCapacity();
    }
    return try result.toOwnedSlice(allocator);
}

// ──── RectClip Path Extraction ───────────────────────────────────────────────

/// OutPt2 체인에서 공선 점을 제거하고 Point 배열로 변환.
fn rectClipGetPath(op: *?*OutPt2, allocator: std.mem.Allocator) []Point {
    if (op.* == null or op.*.?.next == op.*.?.prev) return &[_]Point{};
    var op2 = op.*.?.next;
    while (op2 != null and op2 != op.*) {
        if (isCollinear(op2.?.prev.?.pt, op2.?.pt, op2.?.next.?.pt)) {
            op.* = op2.?.prev;
            // unlink op2
            op2.?.prev.?.next = op2.?.next;
            op2.?.next.?.prev = op2.?.prev;
            op2 = op2.?.next;
        } else {
            op2 = op2.?.next;
        }
    }
    op.* = op2;
    if (op2 == null) return &[_]Point{};
    var result = std.ArrayList(Point).empty;
    result.append(allocator, op.*.?.pt) catch return &[_]Point{};
    op2 = op.*.?.next;
    while (op2 != op.*) {
        result.append(allocator, op2.?.pt) catch return &[_]Point{};
        op2 = op2.?.next;
    }
    return result.toOwnedSlice(allocator) catch &[_]Point{};
}

// ──── RectClip Edge Management ───────────────────────────────────────────────

/// 모든 결과 점을 검사하여 공선 점 제거 및 엣지 배정.
fn rectClipCheckEdges(rc: *RectClip64, allocator: std.mem.Allocator) void {
    for (0..rc.results.items.len) |res_idx| {
        var op = rc.results.items[res_idx] orelse continue;
        var op2: ?*OutPt2 = op;
        while (true) {
            if (isCollinear(op2.?.prev.?.pt, op2.?.pt, op2.?.next.?.pt)) {
                if (op2 == op) {
                    op2 = rectClipUnlinkOpBack(op2.?);
                    if (op2 == null) break;
                    op = op2.?.prev orelse break;
                } else {
                    op2 = rectClipUnlinkOpBack(op2.?);
                    if (op2 == null) break;
                }
            } else {
                op2 = op2.?.next;
            }
            if (op2 == op) break;
        }
        if (op2 == null) {
            rc.results.items[res_idx] = null;
            continue;
        }
        rc.results.items[res_idx] = op;

        var edgeSet1 = rectClipGetEdgesForPt(op.prev.?.pt, rc.rect);
        op2 = op;
        while (true) {
            const edgeSet2 = rectClipGetEdgesForPt(op2.?.pt, rc.rect);
            if (edgeSet2 != 0 and op2.?.edge == null) {
                const combinedSet = edgeSet1 & edgeSet2;
                var j: usize = 0;
                while (j < 4) : (j += 1) {
                    if ((combinedSet & (@as(u32, 1) << @as(u5, @intCast(j)))) != 0) {
                        if (rectClipIsHeadingClockwise2(op2.?.prev.?.pt, op2.?.pt, j)) {
                            rectClipAddToEdge(&rc.edges[j * 2], op2.?, allocator);
                        } else {
                            rectClipAddToEdge(&rc.edges[j * 2 + 1], op2.?, allocator);
                        }
                    }
                }
            }
            edgeSet1 = edgeSet2;
            op2 = op2.?.next;
            if (op2 == op) break;
        }
    }
}

/// OutPt2 링크 해제 (이전 노드 반환). 체인이 비면 null.
fn rectClipUnlinkOpBack(op: *OutPt2) ?*OutPt2 {
    if (op.next == op) return null;
    op.prev.?.next = op.next;
    op.next.?.prev = op.prev;
    return op.prev;
}

/// 점이 사각형의 어느 엣지 위에 있는지 비트마스크로 반환.
/// bit 0: left, bit 1: top, bit 2: right, bit 3: bottom
fn rectClipGetEdgesForPt(pt: Point, rec: RectF64) u32 {
    var result: u32 = 0;
    if (pt.x == rec.left) {
        result = 1;
    } else if (pt.x == rec.right) {
        result = 4;
    }
    if (pt.y == rec.top) {
        result += 2;
    } else if (pt.y == rec.bottom) {
        result += 8;
    }
    return result;
}

/// 엣지 인덱스 기준으로 pt1→pt2가 시계 방향인지.
fn rectClipIsHeadingClockwise2(pt1: Point, pt2: Point, edgeIdx: usize) bool {
    return switch (edgeIdx) {
        0 => pt2.y < pt1.y,
        1 => pt2.x > pt1.x,
        2 => pt2.y > pt1.y,
        else => pt2.x < pt1.x,
    };
}

/// 엣지 리스트에 OutPt2 추가.
fn rectClipAddToEdge(edge: *std.ArrayList(?*OutPt2), op: *OutPt2, allocator: std.mem.Allocator) void {
    if (op.edge != null) return;
    op.edge = edge;
    edge.append(allocator, op) catch {};
}

/// OutPt2에 연결된 엣지에서 제거.
fn rectClipUncoupleEdge(op: *OutPt2) void {
    if (op.edge == null) return;
    const edge = op.edge.?;
    for (0..edge.items.len) |i| {
        if (edge.items[i] == op) {
            edge.items[i] = null;
            break;
        }
    }
    op.edge = null;
}

/// 수평 중첩 검사.
fn rectClipHasHorzOverlap(left1: Point, right1: Point, left2: Point, right2: Point) bool {
    return (left1.x < right2.x) and (right1.x > left2.x);
}

/// 수직 중첩 검사.
fn rectClipHasVertOverlap(top1: Point, bottom1: Point, top2: Point, bottom2: Point) bool {
    return (top1.y < bottom2.y) and (bottom1.y > top2.y);
}

/// 엣지 정리: cw/ccw 리스트 쌍을 처리하여 겹치는 점 연결.
fn rectClipTidyEdges(
    rc: *RectClip64,
    idx: usize,
    cw: *std.ArrayList(?*OutPt2),
    ccw: *std.ArrayList(?*OutPt2),
    allocator: std.mem.Allocator,
) void {
    if (ccw.items.len == 0) return;
    const isHorz = idx == 1 or idx == 3;
    const cwIsTowardLarger = idx == 1 or idx == 2;
    var ci: usize = 0;
    var cj: usize = 0;
    while (ci < cw.items.len) {
        const p1v = cw.items[ci] orelse {
            ci += 1;
            cj = 0;
            continue;
        };
        if (p1v.next == p1v.prev) {
            cw.items[ci] = null;
            ci += 1;
            cj = 0;
            continue;
        }
        const jLim = ccw.items.len;
        while (cj < jLim and (ccw.items[cj] == null or ccw.items[cj].?.next == ccw.items[cj].?.prev)) {
            cj += 1;
        }
        if (cj == jLim) {
            ci += 1;
            cj = 0;
            continue;
        }

        var p1: ?*OutPt2 = undefined;
        var p1a: ?*OutPt2 = undefined;
        var p2: ?*OutPt2 = undefined;
        var p2a: ?*OutPt2 = undefined;
        if (cwIsTowardLarger) {
            p1 = p1v.prev;
            p1a = p1v;
            p2 = ccw.items[cj].?;
            p2a = ccw.items[cj].?.prev;
        } else {
            p1 = p1v;
            p1a = p1v.prev;
            p2 = ccw.items[cj].?.prev;
            p2a = ccw.items[cj].?;
        }
        if ((isHorz and !rectClipHasHorzOverlap(p1.?.pt, p1a.?.pt, p2.?.pt, p2a.?.pt)) or
            (!isHorz and !rectClipHasVertOverlap(p1.?.pt, p1a.?.pt, p2.?.pt, p2a.?.pt)))
        {
            cj += 1;
            continue;
        }
        const isRejoining = p1v.owner_idx != ccw.items[cj].?.owner_idx;
        if (isRejoining) {
            rc.results.items[p2.?.owner_idx] = null;
            rectClipSetNewOwner(p2.?, p1.?.owner_idx);
        }
        if (cwIsTowardLarger) {
            p1.?.next = p2;
            p2.?.prev = p1;
            p1a.?.prev = p2a;
            p2a.?.next = p1a;
        } else {
            p1.?.prev = p2;
            p2.?.next = p1;
            p1a.?.next = p2a;
            p2a.?.prev = p1a;
        }
        if (!isRejoining) {
            const new_idx = rc.results.items.len;
            rc.results.append(allocator, p1a) catch {
                ci += 1;
                continue;
            };
            rectClipSetNewOwner(p1a.?, new_idx);
        }
        ci += 1;
    }
}

/// 체인의 모든 점에 owner_idx 설정.
fn rectClipSetNewOwner(op: *OutPt2, new_idx: usize) void {
    op.owner_idx = new_idx;
    var op2 = op.next;
    while (op2 != op) {
        op2.?.owner_idx = new_idx;
        op2 = op2.?.next;
    }
}

// ============================================================================
// Stage 5b: RectClipLines64 (Line Clipping)
// Odin clipper.odin lines 3185~3242 포팅
// ============================================================================

/// 열린 경로(라인)에 대한 RectClip 실행.
fn rectClipLinesExecuteInternal(rc: *RectClip64, path: []const Point, allocator: std.mem.Allocator) void {
    if (path.len < 2) return;
    rc.results.clearRetainingCapacity();
    rc.start_locs.clearRetainingCapacity();

    var i: usize = 1;
    const highI = path.len - 1;
    var prev: Location = .Inside;
    var loc: Location = .Inside;
    var crossing_loc: Location = .Inside;

    if (!rectClipGetLocation(rc.rect, path[0], &loc)) {
        while (i <= highI and !rectClipGetLocation(rc.rect, path[i], &prev)) {
            i += 1;
        }
        if (i > highI) {
            for (path) |pt| {
                _ = rectClipAdd(rc, pt, false, allocator);
            }
            return;
        }
        if (prev == .Inside) loc = .Inside;
        i = 1;
    }
    if (loc == .Inside) {
        _ = rectClipAdd(rc, path[0], false, allocator);
    }

    while (i <= highI) {
        prev = loc;
        rectClipGetNextLocation(rc, path, &loc, &i, highI, allocator);
        if (i > highI) break;
        const prev_pt = path[i - 1];
        crossing_loc = loc;
        var ip: Point = .{ .x = 0, .y = 0 };
        var ip2: Point = .{ .x = 0, .y = 0 };

        if (!rectClipGetIntersection(rc, path[i], prev_pt, &crossing_loc, &ip)) {
            i += 1;
            continue;
        }
        if (loc == .Inside) {
            // entering
            _ = rectClipAdd(rc, ip, true, allocator);
        } else if (prev != .Inside) {
            // passing through
            crossing_loc = prev;
            _ = rectClipGetIntersection(rc, prev_pt, path[i], &crossing_loc, &ip2);
            _ = rectClipAdd(rc, ip2, true, allocator);
            _ = rectClipAdd(rc, ip, false, allocator);
        } else {
            // exiting
            _ = rectClipAdd(rc, ip, false, allocator);
        }
    }
}

/// OutPt2 체인에서 라인 경로 추출 (시작점은 첫 번째 점).
fn rectClipLinesGetPath(op: *?*OutPt2, allocator: std.mem.Allocator) []Point {
    if (op.* == null or op.* == op.*.?.next) return &[_]Point{};
    op.* = op.*.?.next; // 경로 시작점으로 이동
    var result = std.ArrayList(Point).empty;
    result.append(allocator, op.*.?.pt) catch return &[_]Point{};
    var op2 = op.*.?.next;
    while (op2 != op.*) {
        result.append(allocator, op2.?.pt) catch return &[_]Point{};
        op2 = op2.?.next;
    }
    return result.toOwnedSlice(allocator) catch &[_]Point{};
}

// ──── Output Assembly (buildPath64, buildPaths64, cleanCollinear) ───────────

/// OutPt 연결 리스트를 Point 배열로 변환.
fn buildPath64(op: ?*OutPt, reverse: bool, _isOpen: bool, path: *std.ArrayList(Point), allocator: std.mem.Allocator) bool {
    if (op == null or op.?.next == op or (!_isOpen and op.?.next == op.?.prev)) {
        return false;
    }
    path.items.len = 0; // clear retaining capacity

    var start = op;
    var lastPt = op.?.pt;
    var op2: ?*OutPt = null;
    if (reverse) {
        lastPt = op.?.pt;
        op2 = op.?.prev;
    } else {
        start = op.?.next;
        lastPt = start.?.pt;
        op2 = start.?.next;
    }
    path.append(allocator, lastPt) catch return false;

    while (op2 != start) {
        if (@abs(op2.?.pt.x - lastPt.x) > Eps or @abs(op2.?.pt.y - lastPt.y) > Eps) {
            lastPt = op2.?.pt;
            path.append(allocator, lastPt) catch return false;
        }
        if (reverse) {
            op2 = op2.?.prev;
        } else {
            op2 = op2.?.next;
        }
    }

    if (!isOpen and path.items.len == 3 and isVerySmallTriangle(op2)) {
        return false;
    }
    return true;
}

/// 열린 경로 유효성 검사.
fn isValidOpenPath(op: ?*OutPt) bool {
    if (op == null) return false;
    if (op.?.next == op) return false;
    // 열린 경로는 최소 2점 필요
    var cnt: usize = 0;
    var cur = op;
    while (cur) |c| {
        cnt += 1;
        cur = c.next;
        if (cur == op) break;
    }
    return cnt >= 2;
}

/// 경로들 빌드.
fn buildPaths64(cb: *ClipperBase, solutionClosed: *std.ArrayList([]Point), solutionOpen: *std.ArrayList([]Point), allocator: std.mem.Allocator) void {
    for (cb.outrec_list.items) |rec_opt| {
        const outrec = rec_opt orelse continue;
        if (outrec.pts == null) continue;

        const path = outrec.path;
        if (solutionOpen != null and outrec.is_open) {
            if (isValidOpenPath(outrec.pts) and buildPath64(outrec.pts, cb.reverse_solution, true, &path, allocator)) {
                solutionOpen.?.append(allocator, path.toOwnedSlice(allocator) catch continue) catch {};
            }
        } else {
            // closed path
            if (buildPath64(outrec.pts, cb.reverse_solution, false, &path, allocator)) {
                solutionClosed.append(allocator, path.toOwnedSlice(allocator) catch continue) catch {};
            }
        }
    }
}

/// 공선 정리 (stub).
fn cleanCollinear(cb: *ClipperBase, outrec: *OutRec) void {
    _ = cb;
    _ = outrec;
    // simplified: just get the real outrec and check path validity
    // full CleanCollinear with FixSelfIntersects is deferred
}

// ──── InflatePaths (Offset) Implementation ───────────────────────────────────
// Port of Clipper2 clipper.offset.cpp

/// 점들의 closed path info 로부터 lowest index 와 area 부호 판별
fn getLowestClosedPathInfo(
    paths: []const []Point,
    idx: *i32,
    is_neg_area: *bool,
) void {
    idx.* = -1;
    var bot_pt = Point{ .x = std.math.floatMax(f64), .y = -std.math.floatMax(f64) };

    for (paths, 0..) |path, i| {
        var area: f64 = std.math.floatMax(f64);
        for (path) |pt| {
            if (pt.y > bot_pt.y or (pt.y == bot_pt.y and pt.x <= bot_pt.x)) continue;
            if (area == std.math.floatMax(f64)) {
                // calc area
                area = 0.0;
                for (path, 0..) |p, j| {
                    const k = (j + 1) % path.len;
                    area += p.x * path[k].y - path[k].x * p.y;
                }
                area *= 0.5;
                if (area == 0) break;
                is_neg_area.* = area < 0;
            }
            idx.* = @as(i32, @intCast(i));
            bot_pt.x = pt.x;
            bot_pt.y = pt.y;
            break; // 첫 번째 valid path 만 처리
        }
        if (idx.* != -1) break;
    }
}

/// hypot(x, y): x² + y²의 제곱근
fn hypot(x: f64, y: f64) f64 {
    return std.math.sqrt(x * x + y * y);
}

/// p1→p2 의 단위 법선 벡터 반환
fn getUnitNormal(p1: Point, p2: Point) Point {
    if (p1.x == p2.x and p1.y == p2.y) return .{ .x = 0, .y = 0 };
    const dx = p2.x - p1.x;
    const dy = p2.y - p1.y;
    const inv = 1.0 / hypot(dx, dy);
    return .{ .x = dy * inv, .y = -dx * inv };
}

/// v 가 거의 0 인지 판별
fn almostZero(v: f64, eps: f64) bool {
    return @abs(v) < eps;
}

/// 벡터 v 를 단위 벡터로 정규화
fn normalizeVector(v: Point) Point {
    const h = hypot(v.x, v.y);
    if (almostZero(h, Eps)) return .{ .x = 0, .y = 0 };
    const inv = 1.0 / h;
    return .{ .x = v.x * inv, .y = v.y * inv };
}

/// 두 단위 벡터 v1, v2 의 평균 단위 벡터 반환
fn getAvgUnitVector(v1: Point, v2: Point) Point {
    return normalizeVector(.{ .x = v1.x + v2.x, .y = v1.y + v2.y });
}

/// EndType 이 Polygon 또는 Joined 인지 확인
fn isClosedPath(et: EndType) bool {
    return et == .Polygon or et == .Joined;
}

/// perp(delta) = pt + norm * delta 계산
fn getPerpendic(pt: Point, norm: Point, delta: f64) Point {
    return .{ .x = pt.x + norm.x * delta, .y = pt.y + norm.y * delta };
}

/// 경로 방향 반전 (포인트 부호 반전)
fn negatePath(s: []Point) void {
    for (s) |*pt| {
        pt.x = -pt.x;
        pt.y = -pt.y;
    }
}

// ──── Group init ─────────────────────────────────────────────────────────────

/// 그룹 초기화
fn groupInit(
    g: *Group,
    paths_in: [][]Point,
    jt: JoinType,
    et: EndType,
    allocator: std.mem.Allocator,
) !void {
    g.paths_in = std.ArrayList([]Point).empty;
    for (paths_in) |path| {
        const owned = try allocator.dupe(Point, path);
        try g.paths_in.append(allocator, owned);
    }
    g.join_type = jt;
    g.end_type = et;
    g.is_reversed = false;
    g.lowest_path_idx = -1;

    // strip duplicates
    const is_joined = et == .Polygon or et == .Joined;
    for (g.paths_in.items) |*path| {
        stripDuplicates(path.*, is_joined);
    }

    if (et == .Polygon) {
        var is_neg_area: bool = false;
        getLowestClosedPathInfo(g.paths_in.items, &g.lowest_path_idx, &is_neg_area);
        g.is_reversed = g.lowest_path_idx >= 0 and is_neg_area;
    }
}

/// 중복 제거
fn stripDuplicates(path: []Point, is_closed: bool) void {
    if (path.len <= 1) return;
    var j: usize = 1;
    var i: usize = 1;
    while (i < path.len) : (i += 1) {
        if (path[i].x != path[j - 1].x or path[i].y != path[j - 1].y) {
            path[j] = path[i];
            j += 1;
        }
    }
    if (is_closed and j > 1) {
        if (path[j - 1].x == path[0].x and path[j - 1].y == path[0].y) {
            j -= 1;
        }
    }
    // Note: length can't be resized in-place (borrowed slice),
    // but j tracks the effective end for subsequent iteration.
}

// ──── Offset methods ─────────────────────────────────────────────────────────

/// 법선 벡터 계산 및 저장
fn buildNormals(co: *ClipperOffset, path: []Point, allocator: std.mem.Allocator) !void {
    co.norms.clearRetainingCapacity();
    if (path.len == 0) return;
    try co.norms.ensureTotalCapacity(allocator, path.len);
    var i: usize = 0;
    while (i < path.len - 1) : (i += 1) {
        try co.norms.append(allocator, getUnitNormal(path[i], path[i + 1]));
    }
    try co.norms.append(allocator, getUnitNormal(path[path.len - 1], path[0]));
}

/// bevel 처리
fn doBevel(co: *ClipperOffset, path: []Point, j: usize, k: usize) void {
    var p1: Point = undefined;
    var p2: Point = undefined;
    const abs_delta = @abs(co.group_delta);
    if (j == k) {
        p1 = .{ .x = path[j].x - abs_delta * co.norms.items[j].x, .y = path[j].y - abs_delta * co.norms.items[j].y };
        p2 = .{ .x = path[j].x + abs_delta * co.norms.items[j].x, .y = path[j].y + abs_delta * co.norms.items[j].y };
    } else {
        p1 = .{ .x = path[j].x + co.group_delta * co.norms.items[k].x, .y = path[j].y + co.group_delta * co.norms.items[k].y };
        p2 = .{ .x = path[j].x + co.group_delta * co.norms.items[j].x, .y = path[j].y + co.group_delta * co.norms.items[j].y };
    }
    co.path_out.appendAssumeCapacity(p1);
    co.path_out.appendAssumeCapacity(p2);
}

// 사각형 처리 (Square) — 단순화 버전
fn doSquare(co: *ClipperOffset, path: []Point, j: usize, k: usize, allocator: std.mem.Allocator) !void {
    var vec = Point{ .x = 0, .y = 0 };
    if (j == k) {
        vec = .{ .x = co.norms.items[j].y, .y = -co.norms.items[j].x };
    } else {
        vec = getAvgUnitVector(
            .{ .x = -co.norms.items[k].y, .y = co.norms.items[k].x },
            .{ .x = co.norms.items[j].y, .y = -co.norms.items[j].x },
        );
    }
    const abs_delta = @abs(co.group_delta);
    const ptQ: Point = .{ .x = path[j].x + abs_delta * vec.x, .y = path[j].y + abs_delta * vec.y };

    const pt1: Point = .{ .x = ptQ.x + co.group_delta * vec.y, .y = ptQ.y - co.group_delta * vec.x };
    const pt2: Point = .{ .x = ptQ.x - co.group_delta * vec.y, .y = ptQ.y + co.group_delta * vec.x };
    const pt3 = getPerpendic(path[k], co.norms.items[k], co.group_delta);

    if (j == k) {
        const pt4: Point = .{ .x = pt3.x + vec.x * co.group_delta, .y = pt3.y + vec.y * co.group_delta };
        var intersect_pt: Point = pt1;
        _ = getLineIntersectPt(pt1, pt2, pt3, pt4, &intersect_pt);
        const r1 = reflectPoint(intersect_pt, ptQ);
        try co.path_out.append(allocator, r1);
        try co.path_out.append(allocator, intersect_pt);
    } else {
        const pt4 = getPerpendic(path[j], co.norms.items[k], co.group_delta);
        var intersect_pt: Point = pt1;
        _ = getLineIntersectPt(pt1, pt2, pt3, pt4, &intersect_pt);
        const r2 = reflectPoint(intersect_pt, ptQ);
        try co.path_out.append(allocator, intersect_pt);
        try co.path_out.append(allocator, r2);
    }
}

/// 미터 처리
fn doMiter(co: *ClipperOffset, path: []Point, j: usize, k: usize, cos_a: f64) void {
    const q = co.group_delta / (cos_a + 1.0);
    co.path_out.appendAssumeCapacity(.{
        .x = path[j].x + (co.norms.items[k].x + co.norms.items[j].x) * q,
        .y = path[j].y + (co.norms.items[k].y + co.norms.items[j].y) * q,
    });
}

/// 라운드 처리
fn doRound(co: *ClipperOffset, path: []Point, j: usize, k: usize, angle: f64) void {
    const pt = path[j];
    var offsetVec = Point{
        .x = co.norms.items[k].x * co.group_delta,
        .y = co.norms.items[k].y * co.group_delta,
    };
    if (j == k) {
        offsetVec.x = -offsetVec.x;
        offsetVec.y = -offsetVec.y;
    }
    co.path_out.appendAssumeCapacity(.{ .x = pt.x + offsetVec.x, .y = pt.y + offsetVec.y });

    const steps = @as(usize, @intFromFloat(std.math.ceil(co.steps_per_rad * @abs(angle))));
    var i: usize = 1;
    while (i < steps) : (i += 1) {
        const newX = offsetVec.x * co.step_cos - co.step_sin * offsetVec.y;
        const newY = offsetVec.x * co.step_sin + offsetVec.y * co.step_cos;
        offsetVec.x = newX;
        offsetVec.y = newY;
        co.path_out.appendAssumeCapacity(.{ .x = pt.x + offsetVec.x, .y = pt.y + offsetVec.y });
    }

    const perp = getPerpendic(path[j], co.norms.items[j], co.group_delta);
    co.path_out.appendAssumeCapacity(perp);
}


// ──── Group offset execution ──────────────────────────────────────────────────

/// 그룹 오프셋 실행
fn doGroupOffset(co: *ClipperOffset, group: *Group, allocator: std.mem.Allocator) !void {
    if (group.end_type == .Polygon) {
        if (group.lowest_path_idx < 0) co.delta = @abs(co.delta);
        co.group_delta = if (group.is_reversed) -co.delta else co.delta;
    } else {
        co.group_delta = @abs(co.delta);
    }

    co.join_type = group.join_type;
    co.end_type = group.end_type;

    // 라운드용 스탭 계산
    if (group.join_type == .Round or group.end_type == .Round) {
        var arc_tol: f64 = if (@abs(co.group_delta) < 0.35) 0.15 else @abs(co.group_delta) * 0.002;
        if (co.arc_tolerance > 0.01) {
            arc_tol = @min(@abs(co.group_delta), co.arc_tolerance);
        }
        const steps_per_360 = @min(std.math.pi / std.math.acos(1 - arc_tol / @abs(co.group_delta)), @abs(co.group_delta) * std.math.pi);
        co.step_sin = std.math.sin(2 * std.math.pi / steps_per_360);
        co.step_cos = std.math.cos(2 * std.math.pi / steps_per_360);
        if (co.group_delta < 0) co.step_sin = -co.step_sin;
        co.steps_per_rad = steps_per_360 / (2 * std.math.pi);
    }

    for (group.paths_in.items) |path_in| {
        const pathLen = path_in.len;
        co.path_out.clearRetainingCapacity();
        if (pathLen == 0) continue;

        if (pathLen == 1) {
            const pt = path_in[0];
            if (co.group_delta < 1) continue;
            if (group.join_type == .Round) {
                // ellipse points
                const radius = @abs(co.group_delta);
                const steps = @as(usize, @intFromFloat(std.math.ceil(co.steps_per_rad * 2 * std.math.pi)));
                ellipsePoints(&co.path_out, pt, radius, radius, steps);
            } else {
                const d = @as(usize, @intFromFloat(std.math.ceil(@abs(co.group_delta))));
                try pathRect(&co.path_out, pt, d, allocator);
            }
            try co.solution.?.append(allocator, try allocator.dupe(Point, co.path_out.items));
            continue;
        }

        if (pathLen == 2 and group.end_type == .Joined) {
            if (group.join_type == .Round) {
                co.end_type = .Round;
            } else {
                co.end_type = .Square;
            }
        }

        try buildNormals(co, path_in, allocator);
        
        switch (co.end_type) {
            .Polygon => {
                try offsetPolygon(co, path_in, allocator);
            },
            .Joined => {
                try offsetOpenJoined(co, path_in, allocator);
            },
            else => {
                try offsetOpenPath(co, path_in, allocator);
            },
        }
    }
}

/// 타원점 생성
fn ellipsePoints(path_out: *std.ArrayList(Point), center: Point, rx: f64, ry: f64, steps: usize) void {
    path_out.clearRetainingCapacity();
    const si = std.math.sin(2 * std.math.pi / @as(f64, @floatFromInt(steps)));
    const cs = std.math.cos(2 * std.math.pi / @as(f64, @floatFromInt(steps)));
    var dx: f64 = cs;
    var dy: f64 = si;
    var i: usize = 0;
    while (i < steps) : (i += 1) {
        path_out.appendAssumeCapacity(.{ .x = center.x + rx * dx, .y = center.y + ry * dy });
        const nx = dx * cs - dy * si;
        dy = dy * cs + dx * si;
        dx = nx;
    }
}

/// 점 주변 사각형 생성
fn pathRect(path_out: *std.ArrayList(Point), center: Point, d: usize, allocator: std.mem.Allocator) !void {
    path_out.clearRetainingCapacity();
    const fd = @as(f64, @floatFromInt(d));
    try path_out.append(allocator, .{ .x = center.x - fd, .y = center.y - fd });
    try path_out.append(allocator, .{ .x = center.x + fd, .y = center.y - fd });
    try path_out.append(allocator, .{ .x = center.x + fd, .y = center.y + fd });
    try path_out.append(allocator, .{ .x = center.x - fd, .y = center.y + fd });
}

// 동일한 2D 점 판별
fn same2D(a: Point, b: Point) bool {
    return a.x == b.x and a.y == b.y;
}

/// 내부 포인트를 중립 타입으로 변환
fn toNeutral(p: Point) Point {
    return p;
}

/// 슬라이스 뒤집기
fn reverseSlice(s: []Point) void {
    var i: usize = 0;
    while (i < s.len / 2) : (i += 1) {
        const j = s.len - 1 - i;
        const temp = s[i];
        s[i] = s[j];
        s[j] = temp;
    }
}

// ──── Offset Core Logic (offsetPoint / offsetPolygon / offsetOpenJoined / offsetOpenPath) ──

/// 코너 포인트 오프셋 처리 (Miter/Bevel/Round/Square join)
fn offsetPoint(co: *ClipperOffset, path: []Point, j: usize, k: usize, allocator: std.mem.Allocator) !void {
    if (path[j].x == path[k].x and path[j].y == path[k].y) return;

    var sin_a = cross(co.norms.items[j], co.norms.items[k]);
    const cos_a = dot(co.norms.items[j], co.norms.items[k]);
    if (sin_a > 1) sin_a = 1 else if (sin_a < -1) sin_a = -1;

    if (@abs(co.group_delta) <= 1e-12) {
        try co.path_out.append(allocator, path[j]);
        return;
    }

    if (cos_a > -0.999 and (sin_a * co.group_delta < 0)) {
        // concave — use averaged normal for spike tip (matches C++ Clipper2)
        const perpK = getPerpendic(path[j], co.norms.items[k], co.group_delta);
        const avgNorm = Point{
            .x = (co.norms.items[j].x + co.norms.items[k].x) * 0.5,
            .y = (co.norms.items[j].y + co.norms.items[k].y) * 0.5,
        };
        const perpMid = getPerpendic(path[j], avgNorm, co.group_delta);
        const perpJ = getPerpendic(path[j], co.norms.items[j], co.group_delta);
        try co.path_out.append(allocator, perpK);
        try co.path_out.append(allocator, perpMid);
        try co.path_out.append(allocator, perpJ);
    } else if (cos_a > 0.999 and co.join_type != .Round) {
        // almost straight
        doMiter(co, path, j, k, cos_a);
        doMiter(co, path, j, k, cos_a);
    } else if (co.join_type == .Miter) {
        if (cos_a > co.temp_lim - 1) {
            doMiter(co, path, j, k, cos_a);
        } else {
            try doSquare(co, path, j, k, allocator);
        }
    } else if (co.join_type == .Round) {
        doRound(co, path, j, k, std.math.atan2(sin_a, cos_a));
    } else if (co.join_type == .Bevel) {
        doBevel(co, path, j, k);
    } else {
        try doSquare(co, path, j, k, allocator);
    }
}

/// 닫힌 폴리곤 오프셋 실행
fn offsetPolygon(co: *ClipperOffset, path: []Point, allocator: std.mem.Allocator) !void {
    co.path_out.clearRetainingCapacity();
    var k: usize = path.len - 1;
    var j: usize = 0;
    while (j < path.len) : (j += 1) {
        try offsetPoint(co, path, j, k, allocator);
        k = j;
    }
    const out_copy = try allocator.dupe(Point, co.path_out.items);
    if (co.solution) |sol| {
        try sol.append(allocator, out_copy);
    }
}

/// 조인된 열린 경로 오프셋 (양방향)
fn offsetOpenJoined(co: *ClipperOffset, path: []Point, allocator: std.mem.Allocator) !void {
    // forward pass
    try offsetPolygon(co, path, allocator);

    // reverse path
    var rev = try allocator.alloc(Point, path.len);
    var i: usize = 0;
    while (i < path.len) : (i += 1) {
        rev[path.len - 1 - i] = path[i];
    }

    // reverse normals
    reverseSlice(co.norms.items);

    // cyclic shift left by 1
    const first = co.norms.items[0];
    var ni: usize = 0;
    while (ni < co.norms.items.len - 1) : (ni += 1) {
        co.norms.items[ni] = co.norms.items[ni + 1];
    }
    co.norms.items[co.norms.items.len - 1] = first;

    // negate normals (so offset is applied on the other side)
    negatePath(co.norms.items);

    // backward pass
    try offsetPolygon(co, path, allocator);
}

/// 열린 경로 오프셋 (cap 처리 포함)
fn offsetOpenPath(co: *ClipperOffset, path: []Point, allocator: std.mem.Allocator) !void {
    co.path_out.clearRetainingCapacity();
    const highI = path.len - 1;

    // start cap
    if (@abs(co.group_delta) <= 1e-12) {
        try co.path_out.append(allocator, path[0]);
    } else {
        switch (co.end_type) {
            .Butt => doBevel(co, path, 0, 0),
            .Round => doRound(co, path, 0, 0, std.math.pi),
            else => try doSquare(co, path, 0, 0, allocator),
        }
    }

    // left side forward
    var j: usize = 1;
    while (j < highI) : (j += 1) {
        try offsetPoint(co, path, j, j - 1, allocator);
    }

    // reverse normals for return pass
    var ri: usize = highI;
    while (ri > 0) : (ri -= 1) {
        co.norms.items[ri] = Point{
            .x = -co.norms.items[ri - 1].x,
            .y = -co.norms.items[ri - 1].y,
        };
    }
    co.norms.items[0] = co.norms.items[highI];

    // end cap
    if (@abs(co.group_delta) <= 1e-12) {
        try co.path_out.append(allocator, path[highI]);
    } else {
        switch (co.end_type) {
            .Butt => doBevel(co, path, highI, highI),
            .Round => doRound(co, path, highI, highI, std.math.pi),
            else => try doSquare(co, path, highI, highI, allocator),
        }
    }

    // right side reverse
    j = highI - 1;
    while (j > 0) : (j -= 1) {
        try offsetPoint(co, path, j, j + 1, allocator);
    }

    const out_copy = try allocator.dupe(Point, co.path_out.items);
    if (co.solution) |sol| {
        try sol.append(allocator, out_copy);
    }
}

// ──── Offset execute internal ──────────────────────────────────────────────────

/// 모든 그룹에 대해 오프셋 실행
fn offsetExecuteInternal(co: *ClipperOffset, delta: f64, allocator: std.mem.Allocator) !void {
    if (co.groups.items.len == 0) return;
    co.delta = delta;
    for (co.groups.items) |*g| {
        try doGroupOffset(co, g, allocator);
    }
}

// ──── InflatePaths Public API ────────────────────────────────────────────────

pub const InflateResult = struct {
    res: [][]Point,
    err: ?ClipperError,
};

/// 경로를 지정한 거리만큼 팽창/수축
pub fn inflatePaths(
    paths: [][]Point,
    delta: f64,
    join_type: JoinType,
    end_type: EndType,
    miter_limit: f64,
    arc_tolerance: f64,
    preserve_collinear: bool,
    allocator: std.mem.Allocator,
) InflateResult {
    var co: ClipperOffset = undefined;
    co.miter_limit = miter_limit;
    co.arc_tolerance = arc_tolerance;
    co.preserve_collinear = preserve_collinear;
    co.reverse_solution = false;
    co.temp_lim = if (miter_limit > 1) (@as(f64, 2.0) / (miter_limit * miter_limit)) else 0.5;

    // solution list setup
    var solution_list = std.ArrayList([]Point).empty;
    co.solution = &solution_list;

    co.norms = std.ArrayList(Point).empty;
    co.path_out = std.ArrayList(Point).empty;
    co.groups = std.ArrayList(Group).empty;
    defer {
        for (co.groups.items) |*g| {
            for (g.paths_in.items) |p| {
                allocator.free(p);
            }
            g.paths_in.deinit(allocator);
        }
        co.groups.deinit(allocator);
        co.norms.deinit(allocator);
        co.path_out.deinit(allocator);
    }

    // 각 경로를 별도 그룹으로 등록
    for (paths) |path| {
        if (path.len == 0) continue;
        var g: Group = .{
            .paths_in = undefined,
            .lowest_path_idx = -1,
            .is_reversed = false,
            .join_type = join_type,
            .end_type = end_type,
        };
        var path_wrapper = [_][]Point{path};
        groupInit(&g, &path_wrapper, join_type, end_type, allocator) catch |err| {
            if (err == error.OutOfMemory) {
                return InflateResult{ .res = &[_][]Point{}, .err = error.OutOfMemory };
            }
            return InflateResult{ .res = &[_][]Point{}, .err = error.Failed };
        };
        co.groups.append(allocator, g) catch return InflateResult{ .res = &[_][]Point{}, .err = error.OutOfMemory };
    }

    if (co.groups.items.len == 0) {
        return InflateResult{ .res = &[_][]Point{}, .err = null };
    }

    offsetExecuteInternal(&co, delta, allocator) catch |err| {
        if (err == error.OutOfMemory) {
            return InflateResult{ .res = &[_][]Point{}, .err = error.OutOfMemory };
        }
        return InflateResult{ .res = &[_][]Point{}, .err = error.Failed };
    };

    // 결과 수집 (solution_list → owned slices)
    var result_list = std.ArrayList([]Point).empty;
    defer result_list.deinit(allocator);
    for (solution_list.items) |p| {
        const owned = allocator.dupe(Point, p) catch return InflateResult{ .res = &[_][]Point{}, .err = error.OutOfMemory };
        result_list.append(allocator, owned) catch {
            allocator.free(owned);
            return InflateResult{ .res = &[_][]Point{}, .err = error.OutOfMemory };
        };
    }

    return InflateResult{
        .res = result_list.toOwnedSlice(allocator) catch return InflateResult{ .res = &[_][]Point{}, .err = error.OutOfMemory },
        .err = null,
    };
}

// ──── Boolean Operations Public API ───────────────────────────────────────────

pub const BooleanResult = struct {
    res: [][]Point,      // 닫힌 경로
    res_open: [][]Point, // 열린 경로
    err: ?ClipperError,
};

/// 부울 연산 (Union, Intersect, Difference, Xor)
pub fn booleanOp(
    clip_type: ClipType,
    subject_paths: [][]Point,
    clip_paths: [][]Point,
    open_paths: [][]Point,
    fill_rule: FillRule,
    allocator: std.mem.Allocator,
) BooleanResult {
    var cb: ClipperBase = undefined;
    clipperBaseInit(&cb, allocator);
    defer clipperBaseDestroy(&cb);

    // subject paths 추가
    for (subject_paths) |path| {
        if (path.len == 0) continue;
        const ip = allocator.dupe(Point, path) catch return BooleanResult{ .res = &[_][]Point{}, .res_open = &[_][]Point{}, .err = error.OutOfMemory };
        const path_wrapper = &[_][]const Point{ip};
        addPaths(path_wrapper, .Subject, false, &cb.vertex_lists, &cb.minima_list, allocator);
    }

    // clip paths 추가
    for (clip_paths) |path| {
        if (path.len == 0) continue;
        const ip = allocator.dupe(Point, path) catch return BooleanResult{ .res = &[_][]Point{}, .res_open = &[_][]Point{}, .err = error.OutOfMemory };
        const path_wrapper = &[_][]const Point{ip};
        addPaths(path_wrapper, .Clip, false, &cb.vertex_lists, &cb.minima_list, allocator);
    }

    // open paths 추가
    if (open_paths.len > 0) {
        cb.has_open_paths = true;
    }
    for (open_paths) |path| {
        if (path.len == 0) continue;
        const ip = allocator.dupe(Point, path) catch return BooleanResult{ .res = &[_][]Point{}, .res_open = &[_][]Point{}, .err = error.OutOfMemory };
        const path_wrapper = &[_][]const Point{ip};
        addPaths(path_wrapper, .Subject, true, &cb.vertex_lists, &cb.minima_list, allocator);
    }

    executeInternal(&cb, clip_type, fill_rule, allocator) catch |err| {
        if (err == error.OutOfMemory) {
            return BooleanResult{ .res = &[_][]Point{}, .res_open = &[_][]Point{}, .err = error.OutOfMemory };
        }
        return BooleanResult{ .res = &[_][]Point{}, .res_open = &[_][]Point{}, .err = error.Failed };
    };
    if (!cb.succeeded) {
        return BooleanResult{ .res = &[_][]Point{}, .res_open = &[_][]Point{}, .err = error.Failed };
    }

    // 결과 수집
    var closed_list = std.ArrayList([]Point).empty;
    defer closed_list.deinit(allocator);
    var open_list = std.ArrayList([]Point).empty;
    defer open_list.deinit(allocator);
    buildPaths64(&cb, &closed_list, &open_list, allocator);

    return BooleanResult{
        .res = closed_list.toOwnedSlice(allocator) catch return BooleanResult{ .res = &[_][]Point{}, .res_open = &[_][]Point{}, .err = error.OutOfMemory },
        .res_open = open_list.toOwnedSlice(allocator) catch return BooleanResult{ .res = &[_][]Point{}, .res_open = &[_][]Point{}, .err = error.OutOfMemory },
        .err = null,
    };
}

// ──── RectClip Public API ─────────────────────────────────────────────────────

pub const RectClipResult = struct {
    closed: [][]Point,
    open: [][]Point,
    err: ?ClipperError,
};

/// 사각형 클립 (경로들을 사각형으로 클립)
pub fn rectClip(
    rect: RectF64,
    close_paths: [][]Point,
    open_paths: [][]Point,
    allocator: std.mem.Allocator,
) RectClipResult {
    var rc = RectClip64{
        .rect = rect,
        .rect_as_path = undefined,
        .rect_mp = undefined,
        .path_bounds = undefined,
        .op_container = std.ArrayList(OutPt2).empty,
        .results = std.ArrayList(?*OutPt2).empty,
        .edges = undefined,
        .start_locs = std.ArrayList(Location).empty,
    };
    rc.rect = rect;
    rc.rect_as_path[0] = .{ .x = rect.left, .y = rect.top };
    rc.rect_as_path[1] = .{ .x = rect.right, .y = rect.top };
    rc.rect_as_path[2] = .{ .x = rect.right, .y = rect.bottom };
    rc.rect_as_path[3] = .{ .x = rect.left, .y = rect.bottom };
    rc.rect_mp = .{ .x = (rect.left + rect.right) * 0.5, .y = (rect.top + rect.bottom) * 0.5 };

    // close_paths → RectClip64 execute
    var closed_list = std.ArrayList([]Point).empty;
    defer closed_list.deinit(allocator);

    if (close_paths.len > 0) {
        // convert paths to internal format ([]const Point)
        const internal = allocator.alloc([]const Point, close_paths.len) catch
            return RectClipResult{ .closed = &[_][]Point{}, .open = &[_][]Point{}, .err = error.OutOfMemory };
        defer allocator.free(internal);
        for (close_paths, 0..) |path, i| {
            internal[i] = path; // borrow — rectClipExecute copies internally
        }

        const raw = rectClipExecute(&rc, internal, allocator) catch |err| {
            if (err == error.OutOfMemory) {
                return RectClipResult{ .closed = &[_][]Point{}, .open = &[_][]Point{}, .err = error.OutOfMemory };
            }
            return RectClipResult{ .closed = &[_][]Point{}, .open = &[_][]Point{}, .err = error.Failed };
        };
        for (raw) |rp| {
            closed_list.append(allocator, rp) catch return RectClipResult{ .closed = &[_][]Point{}, .open = &[_][]Point{}, .err = error.OutOfMemory };
        }
    }

    // open_paths → RectClip64 line clipping
    var open_list = std.ArrayList([]Point).empty;
    defer open_list.deinit(allocator);

    if (open_paths.len > 0) {
        for (open_paths) |op| {
            if (op.len < 2) continue;
            var rc2: RectClip64 = undefined;
            rc2.rect = rc.rect;
            rc2.rect_as_path = rc.rect_as_path;
            rc2.rect_mp = rc.rect_mp;
            rc2.results = .empty;
            rc2.start_locs = .empty;
            const owned = allocator.dupe(Point, op) catch
                return RectClipResult{ .closed = &[_][]Point{}, .open = &[_][]Point{}, .err = error.OutOfMemory };
            rectClipLinesExecuteInternal(&rc2, owned, allocator);
            for (rc2.results.items, 0..) |res_opt, idx| {
                if (res_opt) |_| {
                    const tmp = rectClipLinesGetPath(&rc2.results.items[idx], allocator);
                    if (tmp.len > 0) {
                        open_list.append(allocator, tmp) catch {
                            allocator.free(tmp);
            return RectClipResult{ .closed = &[_][]Point{}, .open = &[_][]Point{}, .err = error.OutOfMemory };
                        };
                    }
                }
            }
            rc2.results.clearRetainingCapacity();
            allocator.free(owned);
        }
    }

    return RectClipResult{
        .closed = closed_list.toOwnedSlice(allocator) catch return RectClipResult{ .closed = &[_][]Point{}, .open = &[_][]Point{}, .err = error.OutOfMemory },
        .open = open_list.toOwnedSlice(allocator) catch return RectClipResult{ .closed = &[_][]Point{}, .open = &[_][]Point{}, .err = error.OutOfMemory },
        .err = null,
    };
}
