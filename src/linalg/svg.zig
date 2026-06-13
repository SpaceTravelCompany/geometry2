//! svg.zig — Odin shared/geometry/svg/svg.odin 1:1 포팅.
//! plutovg + zig-xml을 사용한 SVG 경로 파싱.

const std = @import("std");
const linalg = @import("linalg.zig");
const Vec2f32 = linalg.Vec2f32;
const Vec4f32 = linalg.Vec4f32;
const geometry = @import("geometry.zig");
const ShapeNode = geometry.ShapeNode;
const Shapes = geometry.Shapes;
const ShapeError = geometry.ShapeError;
const isHoleContour = geometry.isHoleContour;
const reverseShapeCloseCurve = geometry.reverseShapeCloseCurve;
const linalg_mod = @import("mod.zig");
const getPolygonOrientation = linalg_mod.getPolygonOrientation;
const xml = @import("xml");

// ══════════════════════════════════════════════════════════════════════════════
//  plutovg C-ABI 선언
// ══════════════════════════════════════════════════════════════════════════════

const plutovg_point_t = extern struct {
    x: f32,
    y: f32,
};

const plutovg_color_t = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

const plutovg_matrix_t = extern struct {
    a: f32,
    b: f32,
    c: f32,
    d: f32,
    e: f32,
    f: f32,
};

const plutovg_path_t = opaque {};
const plutovg_surface_t = opaque {};
const plutovg_canvas_t = opaque {};

const plutovg_path_command_t = c_int;
pub const PLUTOVG_PATH_COMMAND_MOVE_TO: plutovg_path_command_t = 0;
pub const PLUTOVG_PATH_COMMAND_LINE_TO: plutovg_path_command_t = 1;
pub const PLUTOVG_PATH_COMMAND_CUBIC_TO: plutovg_path_command_t = 2;
pub const PLUTOVG_PATH_COMMAND_CLOSE: plutovg_path_command_t = 3;

const plutovg_path_element_t = extern struct {
    header: plutovg_path_element_header_t,
    point: plutovg_point_t,
};

const plutovg_path_element_header_t = extern struct {
    command: plutovg_path_command_t,
    length: c_int,
};

const plutovg_path_iterator_t = extern struct {
    elements: [*]plutovg_path_element_t,
    size: c_int,
    index: c_int,
};

extern "c" fn plutovg_path_create() ?*plutovg_path_t;
extern "c" fn plutovg_path_destroy(path: ?*plutovg_path_t) void;
extern "c" fn plutovg_path_parse(path: ?*plutovg_path_t, data: [*c]const u8, length: c_int) bool;
extern "c" fn plutovg_path_transform(path: ?*plutovg_path_t, mat: *const plutovg_matrix_t) void;
extern "c" fn plutovg_path_iterator_init(it: *plutovg_path_iterator_t, path: ?*plutovg_path_t) void;
extern "c" fn plutovg_path_iterator_has_next(it: *const plutovg_path_iterator_t) bool;
extern "c" fn plutovg_path_iterator_next(it: *plutovg_path_iterator_t, points: *[3]plutovg_point_t) plutovg_path_command_t;
extern "c" fn plutovg_matrix_parse(mat: *plutovg_matrix_t, data: [*c]const u8, length: c_int) bool;
extern "c" fn plutovg_color_parse(color: *plutovg_color_t, data: [*c]const u8, length: c_int) c_int;

// ══════════════════════════════════════════════════════════════════════════════
//  null-terminated string helper for C interop
// ══════════════════════════════════════════════════════════════════════════════

fn cStringBuf(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    const buf = try allocator.alloc(u8, s.len + 1);
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf;
}

// ══════════════════════════════════════════════════════════════════════════════
//  _skipToElementEnd (private) — streaming XML reader 보조
// ══════════════════════════════════════════════════════════════════════════════

/// 현재 element_start 위치에서 matching element_end까지 읽고 건너뛴다.
/// 중첩된 자식 요소도 올바르게 처리한다.
fn skipToElementEnd(reader: *xml.Reader) SvgError!void {
    var depth: u32 = 1;
    while (depth > 0) {
        switch (try reader.read()) {
            .element_start => depth += 1,
            .element_end => depth -= 1,
            .eof => return error.INVALID_NODE,
            else => continue,
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Error
// ══════════════════════════════════════════════════════════════════════════════

pub const SvgError = error{
    NOT_INITIALIZED,
    INVALID_NODE,
    UNSUPPORTED_FEATURE,
    MalformedXml,    // zig-xml reader error
    ReadFailed,      // zig-xml reader error
    OutOfMemory,     // already in Allocator.Error, but explicit for xml reader compatibility
};

// ══════════════════════════════════════════════════════════════════════════════
//  SvgParser
// ══════════════════════════════════════════════════════════════════════════════

pub const SvgParser = struct {
    arenaAllocator: ?std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    shapes: Shapes,

    pub fn deinit(self: *SvgParser) void {
        if (self.arenaAllocator != null) {
            self.arena.deinit();
            self.arenaAllocator = null;
        }
        self.shapes = undefined;
    }
};

// ══════════════════════════════════════════════════════════════════════════════
//  __PathAttr (private)
// ══════════════════════════════════════════════════════════════════════════════

const __PathAttr = struct {
    d: ?[]const u8 = null,
    fill: ?[]const u8 = null,
    fillOpacity: ?f32 = null,
    stroke: ?[]const u8 = null,
    strokeOpacity: ?f32 = null,
    strokeWidth: ?f32 = null,
    transform: ?[]const u8 = null,
};

const _EPS: f32 = 0.0001;

// ══════════════════════════════════════════════════════════════════════════════
//  _isNoneValue (private)
// ══════════════════════════════════════════════════════════════════════════════

fn isNoneValue(s: []const u8) bool {
    if (s.len != 4) return false;
    return (s[0] == 'n' or s[0] == 'N') and
        (s[1] == 'o' or s[1] == 'O') and
        (s[2] == 'n' or s[2] == 'N') and
        (s[3] == 'e' or s[3] == 'E');
}

// ══════════════════════════════════════════════════════════════════════════════
//  _toGeomPoint (private)
// ══════════════════════════════════════════════════════════════════════════════

fn toGeomPoint(p: plutovg_point_t) Vec2f32 {
    return Vec2f32{ .x = p.x, .y = -p.y };
}

// ══════════════════════════════════════════════════════════════════════════════
//  _parseNumberAttr (private)
// ══════════════════════════════════════════════════════════════════════════════

fn parseNumberAttr(value: []const u8) SvgError!f32 {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    return std.fmt.parseFloat(f32, trimmed) catch error.INVALID_NODE;
}

// ══════════════════════════════════════════════════════════════════════════════
//  _setPathAttr (private)
// ══════════════════════════════════════════════════════════════════════════════

fn setPathAttr(key: []const u8, value: []const u8, out: *__PathAttr) SvgError!void {
    if (std.mem.eql(u8, key, "d")) {
        out.d = value;
    } else if (std.mem.eql(u8, key, "fill")) {
        out.fill = value;
    } else if (std.mem.eql(u8, key, "fill-opacity")) {
        out.fillOpacity = try parseNumberAttr(value);
    } else if (std.mem.eql(u8, key, "stroke")) {
        out.stroke = value;
    } else if (std.mem.eql(u8, key, "stroke-opacity")) {
        out.strokeOpacity = try parseNumberAttr(value);
    } else if (std.mem.eql(u8, key, "stroke-width")) {
        out.strokeWidth = try parseNumberAttr(value);
    } else if (std.mem.eql(u8, key, "transform")) {
        out.transform = value;
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _parseStyleAttr (private)
// ══════════════════════════════════════════════════════════════════════════════

fn parseStyleAttr(style: []const u8, out: *__PathAttr) SvgError!void {
    var i: usize = 0;
    while (i < style.len) {
        const declStart = i;
        while (i < style.len and style[i] != ';') i += 1;
        const decl = std.mem.trim(u8, style[declStart..i], " \t\r\n");
        if (i < style.len and style[i] == ';') i += 1;
        if (decl.len == 0) continue;

        if (std.mem.indexOfScalar(u8, decl, ':')) |colon| {
            const key = std.mem.trim(u8, decl[0..colon], " \t\r\n");
            const value = std.mem.trim(u8, decl[colon + 1 ..], " \t\r\n");
            try setPathAttr(key, value, out);
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _parseSvgColor (private)
// ══════════════════════════════════════════════════════════════════════════════

fn parseSvgColor(colorText: []const u8, opacity: ?f32, tempAlloc: std.mem.Allocator) SvgError!?Vec4f32 {
    const value = std.mem.trim(u8, colorText, " \t\r\n");
    if (value.len == 0 or isNoneValue(value)) return null;

    var clr: plutovg_color_t = undefined;
    const buf = try cStringBuf(tempAlloc, value);
    defer tempAlloc.free(buf);

    const consumed = plutovg_color_parse(&clr, buf.ptr, @intCast(value.len));
    if (consumed == 0) return error.INVALID_NODE;

    var alpha = clr.a;
    if (opacity) |o| {
        alpha *= @max(0.0, @min(o, 1.0));
    }
    const color: Vec4f32 = .{ clr.r, clr.g, clr.b, @max(0.0, @min(alpha, 1.0)) };
    if (color[3] <= 0.0) return null;
    return color;
}

// ══════════════════════════════════════════════════════════════════════════════
//  _resetContour (private)
// ══════════════════════════════════════════════════════════════════════════════

fn resetContour(pts: *std.array_list.AlignedManaged(Vec2f32, null), curves: *std.array_list.AlignedManaged(bool, null)) void {
    pts.clearRetainingCapacity();
    curves.clearRetainingCapacity();
}

// ══════════════════════════════════════════════════════════════════════════════
//  _normalizeContourWinding (private)
// ══════════════════════════════════════════════════════════════════════════════

fn normalizeContourWinding(
    ptsOut: *std.array_list.AlignedManaged([]Vec2f32, null),
    curvesOut: *std.array_list.AlignedManaged([]bool, null),
    arena: std.mem.Allocator,
) SvgError!void {
    if (ptsOut.items.len != curvesOut.items.len) return error.INVALID_NODE;

    var i: usize = 0;
    while (i < ptsOut.items.len) {
        const pts = ptsOut.items[i];
        const curves = curvesOut.items[i];
        if (pts.len < 3) {
            i += 1;
            continue;
        }
        if (pts.len != curves.len) return error.INVALID_NODE;

        const isHole = isHoleContour(i, ptsOut.items);
        const orientation = getPolygonOrientation(f32, pts);
        const needReverse = (!isHole and orientation != .CounterClockwise) or
            (isHole and orientation != .Clockwise);

        if (needReverse) {
            if (reverseShapeCloseCurve(pts, curves, arena)) |result| {
                ptsOut.items[i] = result.pts;
                curvesOut.items[i] = result.isCurves;
            } else |err| switch (err) {
                error.Consecutive_Anchor_Missing_Control => {
                    // line-only contour (모든 점이 anchor, curve 없음)는 reverse 불가.
                    // SVG path의 "L" 명령어만으로 만든 closed contour가 이에 해당.
                    // orientation 그대로 유지하고 reverse를 건너뜀.
                },
                else => return error.INVALID_NODE,
            }
        }
        i += 1;
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  _finalizeContour (private)
// ══════════════════════════════════════════════════════════════════════════════

fn finalizeContour(
    inoutPts: *std.array_list.AlignedManaged(Vec2f32, null),
    inoutCurves: *std.array_list.AlignedManaged(bool, null),
    isClosed: bool,
    ptsOut: *std.array_list.AlignedManaged([]Vec2f32, null),
    curvesOut: *std.array_list.AlignedManaged([]bool, null),
    arena: std.mem.Allocator,
) SvgError!void {
    if (inoutPts.items.len == 0) {
        resetContour(inoutPts, inoutCurves);
        return;
    }
    if (inoutPts.items.len != inoutCurves.items.len) return error.INVALID_NODE;

    // 같은 첫/마지막 점이면 마지막 점 제거 (geometry.shapesComputePolygon의 중복 방지)
    if (isClosed and
        inoutPts.items.len > 1 and
        !inoutCurves.items[inoutCurves.items.len - 1] and
        std.meta.eql(inoutPts.items[inoutPts.items.len - 1], inoutPts.items[0]))
    {
        inoutPts.items.len -= 1;
        inoutCurves.items.len -= 1;
    }

    // shapesComputePolygon은 첫 점이 비-커브여야 함.
    // 필요한 경우 contour 시작점을 첫 비-커브 점으로 rotate.
    if (isClosed and inoutCurves.items.len > 0 and inoutCurves.items[0]) {
        var start: isize = -1;
        for (inoutCurves.items, 0..) |isCurve, idx| {
            if (!isCurve) {
                start = @intCast(idx);
                break;
            }
        }
        if (start < 0) return error.INVALID_NODE;

        if (start > 0) {
            const n = inoutPts.items.len;
            var rotPts = try std.array_list.AlignedManaged(Vec2f32, null).initCapacity(arena, n);
            var rotCurves = try std.array_list.AlignedManaged(bool, null).initCapacity(arena, n);
            const s = @as(usize, @intCast(start));
            for (0..n) |j| {
                const src = (s + j) % n;
                rotPts.appendAssumeCapacity(inoutPts.items[src]);
                rotCurves.appendAssumeCapacity(inoutCurves.items[src]);
            }
            inoutPts.deinit();
            inoutCurves.deinit();
            inoutPts.* = rotPts;
            inoutCurves.* = rotCurves;
        }
    }

    if (isClosed and inoutPts.items.len >= 2) {
        const pts_copy = try arena.dupe(Vec2f32, inoutPts.items);
        const curves_copy = try arena.dupe(bool, inoutCurves.items);
        try ptsOut.append(pts_copy);
        try curvesOut.append(curves_copy);
    }

    resetContour(inoutPts, inoutCurves);
}

// ══════════════════════════════════════════════════════════════════════════════
//  _pathToClosedContours (private)
// ══════════════════════════════════════════════════════════════════════════════

fn pathToClosedContours(
    path: ?*plutovg_path_t,
    ptsOut: *std.array_list.AlignedManaged([]Vec2f32, null),
    curvesOut: *std.array_list.AlignedManaged([]bool, null),
    arena: std.mem.Allocator,
) SvgError!void {
    var currentPts = std.array_list.AlignedManaged(Vec2f32, null).init(arena);
    var currentCurves = std.array_list.AlignedManaged(bool, null).init(arena);

    var it: plutovg_path_iterator_t = undefined;
    plutovg_path_iterator_init(&it, path);

    while (plutovg_path_iterator_has_next(&it)) {
        var points: [3]plutovg_point_t = undefined;
        const cmd = plutovg_path_iterator_next(&it, &points);

        switch (cmd) {
            PLUTOVG_PATH_COMMAND_MOVE_TO => {
                try finalizeContour(&currentPts, &currentCurves, true, ptsOut, curvesOut, arena);
                try currentPts.append(toGeomPoint(points[0]));
                try currentCurves.append(false);
            },
            PLUTOVG_PATH_COMMAND_LINE_TO => {
                if (currentPts.items.len == 0) return error.INVALID_NODE;
                try currentPts.append(toGeomPoint(points[0]));
                try currentCurves.append(false);
            },
            PLUTOVG_PATH_COMMAND_CUBIC_TO => {
                if (currentPts.items.len == 0) return error.INVALID_NODE;
                try currentPts.append(toGeomPoint(points[0]));
                try currentPts.append(toGeomPoint(points[1]));
                try currentPts.append(toGeomPoint(points[2]));
                try currentCurves.append(true);
                try currentCurves.append(true);
                try currentCurves.append(false);
            },
            PLUTOVG_PATH_COMMAND_CLOSE => {
                if (currentPts.items.len == 0) continue;
                try finalizeContour(&currentPts, &currentCurves, true, ptsOut, curvesOut, arena);
            },
            else => return error.UNSUPPORTED_FEATURE,
        }
    }

    // Trailing subpath
    try finalizeContour(&currentPts, &currentCurves, true, ptsOut, curvesOut, arena);
}

// ══════════════════════════════════════════════════════════════════════════════
//  _pathElementToShapeNode (private)
// ══════════════════════════════════════════════════════════════════════════════

fn pathElementToShapeNode(reader: *xml.Reader, arena: std.mem.Allocator, tempAlloc: std.mem.Allocator) SvgError!?ShapeNode {
    _ = tempAlloc;

    var attr = __PathAttr{};

    // ianprime0509/zig-xml streaming reader — attribute iteration
    {
        const n = reader.attributeCount();
        for (0..n) |i| {
            const name = reader.attributeName(i);
            const value = try reader.attributeValue(i);
            if (std.mem.eql(u8, name, "style")) {
                try parseStyleAttr(value, &attr);
            } else if (std.mem.eql(u8, name, "d")) {
                try setPathAttr("d", value, &attr);
            } else if (std.mem.eql(u8, name, "fill")) {
                try setPathAttr("fill", value, &attr);
            } else if (std.mem.eql(u8, name, "fill-opacity")) {
                try setPathAttr("fill-opacity", value, &attr);
            } else if (std.mem.eql(u8, name, "stroke")) {
                try setPathAttr("stroke", value, &attr);
            } else if (std.mem.eql(u8, name, "stroke-opacity")) {
                try setPathAttr("stroke-opacity", value, &attr);
            } else if (std.mem.eql(u8, name, "stroke-width")) {
                try setPathAttr("stroke-width", value, &attr);
            } else if (std.mem.eql(u8, name, "transform")) {
                try setPathAttr("transform", value, &attr);
            }
        }
    }

    const d = attr.d orelse return null;

    // fill color
    var fillColor: Vec4f32 = .{ 0.0, 0.0, 0.0, 1.0 };
    var hasFill = true;

    if (attr.fill) |fill| {
        if (try parseSvgColor(fill, attr.fillOpacity, arena)) |c| {
            fillColor = c;
            hasFill = c[3] > 0.0;
        } else {
            hasFill = false;
        }
    } else if (attr.fillOpacity) |fo| {
        fillColor[3] = @max(0.0, @min(fo, 1.0));
        hasFill = fillColor[3] > 0.0;
    }
    if (!hasFill) return null;

    // stroke color
    var strokeColor: Vec4f32 = @splat(0.0);
    var hasStroke = false;
    if (attr.stroke) |stroke| {
        if (try parseSvgColor(stroke, attr.strokeOpacity, arena)) |c| {
            strokeColor = c;
            hasStroke = c[3] > 0.0;
        } else {
            hasStroke = false;
        }
    }
    var strokeWidth: f32 = 0.0;
    if (hasStroke) {
        strokeWidth = 1.0;
        if (attr.strokeWidth) |w| {
            strokeWidth = @max(w, 0.0);
        }
    }

    // plutovg path 파싱
    const path = plutovg_path_create() orelse return error.INVALID_NODE;
    defer plutovg_path_destroy(path);

    const d_trimmed = std.mem.trim(u8, d, " \t\r\n");
    if (d_trimmed.len == 0) return null;

    {
        const buf = try cStringBuf(arena, d_trimmed);
        defer arena.free(buf);
        const ok = plutovg_path_parse(path, buf.ptr, @intCast(d_trimmed.len));
        if (!ok) return error.INVALID_NODE;
    }

    // transform
    if (attr.transform) |t| {
        const t_trimmed = std.mem.trim(u8, t, " \t\r\n");
        if (t_trimmed.len > 0) {
            var mat: plutovg_matrix_t = undefined;
            const tbuf = try cStringBuf(arena, t_trimmed);
            defer arena.free(tbuf);
            const tok = plutovg_matrix_parse(&mat, tbuf.ptr, @intCast(t_trimmed.len));
            if (!tok) return error.INVALID_NODE;
            plutovg_path_transform(path, &mat);
        }
    }

    var pts: std.array_list.AlignedManaged([]Vec2f32, null) = std.array_list.AlignedManaged([]Vec2f32, null).init(arena);
    var curves: std.array_list.AlignedManaged([]bool, null) = std.array_list.AlignedManaged([]bool, null).init(arena);

    try pathToClosedContours(path, &pts, &curves, arena);
    try normalizeContourWinding(&pts, &curves, arena);
    if (pts.items.len == 0) return null;

    return ShapeNode{
        .pts = pts.items,
        .isCurves = curves.items,
        .color = fillColor,
        .strokeColor = strokeColor,
        .thickness = strokeWidth,
        .isClosed = true,
        .clipRect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 },
    };
}

// ══════════════════════════════════════════════════════════════════════════════
//  _parseXmlTree (private) — ianprime0509/zig-xml streaming reader 기반
// ══════════════════════════════════════════════════════════════════════════════

/// 요소 시작 이벤트부터 자식을 재귀적으로 처리한다.
/// 호출 시 reader는 element_start 위치여야 하며, element_end에서 반환된다.
fn parseXmlTree(
    reader: *xml.Reader,
    nodes: *std.array_list.AlignedManaged(ShapeNode, null),
    arena: std.mem.Allocator,
    tempAlloc: std.mem.Allocator,
) SvgError!void {
    while (true) {
        switch (try reader.read()) {
            .element_start => {
                const tag = reader.elementName();
                if (std.mem.eql(u8, tag, "path")) {
                    if (try pathElementToShapeNode(reader, arena, tempAlloc)) |node| {
                        try nodes.append(node);
                    }
                    try skipToElementEnd(reader);
                } else {
                    // 다른 요소(g, defs, clipPath 등)는 자식 재귀 처리
                    try parseXmlTree(reader, nodes, arena, tempAlloc);
                }
            },
            .element_end, .eof => return,
            else => continue,
        }
    }
}

// ══════════════════════════════════════════════════════════════════════════════
//  initParse
// ══════════════════════════════════════════════════════════════════════════════

pub fn initParse(
    svgData: []const u8,
    allocator: std.mem.Allocator,
) SvgError!SvgParser {
    if (svgData.len == 0) return error.INVALID_NODE;

    var arena = std.heap.ArenaAllocator.init(allocator);
    const arena_alloc = arena.allocator();
    errdefer arena.deinit();

    // ianprime0509/zig-xml streaming reader
    var xml_reader = xml.Reader.Static.init(arena_alloc, svgData, .{
        .namespace_aware = false,
    });
    defer xml_reader.deinit();

    var nodes = std.array_list.AlignedManaged(ShapeNode, null).init(arena_alloc);
    // 첫 element_start까지 읽고 parseXmlTree 진입
    while (true) {
        switch (try xml_reader.interface.read()) {
            .element_start => {
                try parseXmlTree(&xml_reader.interface, &nodes, arena_alloc, arena_alloc);
                break;
            },
            .eof => break,
            else => continue,
        }
    }

    return SvgParser{
        .arenaAllocator = arena_alloc,
        .arena = arena,
        .shapes = Shapes{
            .nodes = nodes.items,
            .clipRect = .{ .left = 0, .right = 0, .top = 0, .bottom = 0 },
        },
    };
}
