//! geometry2.linalg — Odin linalg_ex 1:1 포팅.
//! 모든 서브모듈을 재노출한다.

pub const linalg = @import("linalg.zig");

// Vec/Mat 타입은 모듈 최상위에서도 직접 접근 가능하도록 re-export
pub const Vec2 = linalg.Vec2;
pub const Vec2f32 = linalg.Vec2f32;
pub const Vec2f64 = linalg.Vec2f64;
pub const Vec3f32 = linalg.Vec3f32;
pub const Vec4f32 = linalg.Vec4f32;
pub const Mat4x4 = linalg.Mat4x4;
pub const Mat4x4f32 = linalg.Mat4x4f32;

pub const rect = @import("rect.zig");
pub const area = @import("area.zig");
pub const polygon = @import("polygon.zig");
pub const lines = @import("lines.zig");
pub const circle = @import("circle.zig");
pub const bezier = @import("bezier.zig");
pub const bezier_intersect = @import("bezier_intersect.zig");
pub const matrix2d = @import("matrix2d.zig");
pub const triangle = @import("triangle.zig");
pub const mirror = @import("mirror.zig");
pub const point_in = @import("point_in.zig");
pub const path_template = @import("path_template.zig");

// ── rect ──────────────────────────────────────────────────────────────
pub const CenterPtPos = rect.CenterPtPos;
pub const PointInPolygonResult = rect.PointInPolygonResult;
pub const Rect = rect.Rect;
pub const Rectf32 = rect.Rectf32;
pub const Recti32 = rect.Recti32;
pub const Rectu32 = rect.Rectu32;
pub const rectInit = rect.rectInit;
pub const checkRect = rect.checkRect;
pub const rectMulMatrix = rect.rectMulMatrix;
pub const rectDivMatrix = rect.rectDivMatrix;
pub const rectLeftTop = rect.rectLeftTop;
pub const rectRightBottom = rect.rectRightBottom;
pub const rectAnd = rect.rectAnd;
pub const rectOr = rect.rectOr;
pub const rectPointIn = rect.rectPointIn;
pub const rectMove = rect.rectMove;

// ── area ──────────────────────────────────────────────────────────────
pub const Area = area.Area;
pub const Areaf32 = area.Areaf32;
pub const Areaf64 = area.Areaf64;
pub const Areai32 = area.Areai32;
pub const areaMulMatrix = area.areaMulMatrix;
pub const areaPointIn = area.areaPointIn;

// ── polygon ───────────────────────────────────────────────────────────
pub const PolyOrientation = polygon.PolyOrientation;
pub const polygonOverlapsPolygon = polygon.polygonOverlapsPolygon;
pub const pointInPolygon = polygon.pointInPolygon;
pub const centerPointInPolygon = polygon.centerPointInPolygon;
pub const getPolygonOrientation = polygon.getPolygonOrientation;
pub const polygonSignedArea = polygon.polygonSignedArea;
pub const lineInPolygon = polygon.lineInPolygon;

// ── lines ─────────────────────────────────────────────────────────────
pub const IntersectKind = lines.IntersectKind;
pub const linesIntersect2 = lines.linesIntersect2;
pub const linesIntersect3 = lines.linesIntersect3;
pub const pointInLine = lines.pointInLine;
pub const pointDeltaInLine = lines.pointDeltaInLine;
pub const pointInVector = lines.pointInVector;
pub const pointLineLeftOrRight = lines.pointLineLeftOrRight;
pub const crossProductSign = lines.crossProductSign;
pub const dotProduct = lines.dotProduct;
pub const nearestPointBetweenPointAndLine = lines.nearestPointBetweenPointAndLine;
pub const inCircleTest = lines.inCircleTest;
pub const getAngle = lines.getAngle;
pub const subdivLine = lines.subdivLine;
pub const subdivQuadraticBezier = lines.subdivQuadraticBezier;
pub const subdivCubicBezier = lines.subdivCubicBezier;
pub const shortestLength2Line = lines.shortestLength2Line;
pub const epsilon = linalg.epsilon;

// ── circle ────────────────────────────────────────────────────────────
pub const Circle = circle.Circle;
pub const Circlef32 = circle.Circlef32;
pub const Circlef64 = circle.Circlef64;

// ── bezier ────────────────────────────────────────────────────────────
pub const BezierKind = bezier.BezierKind;
pub const evalBezier = bezier.evalBezier;
pub const evalBezierTangent = bezier.evalBezierTangent;
pub const evalBezierSegment = bezier.evalBezierSegment;
pub const cvtQuadraticToCubic0 = bezier.cvtQuadraticToCubic0;
pub const cvtQuadraticToCubic1 = bezier.cvtQuadraticToCubic1;

// ── bezier_intersect ──────────────────────────────────────────────────
pub const MaxBezierIntersections = bezier_intersect.MaxBezierIntersections;
pub const bezierOrder = bezier_intersect.bezierOrder;
pub const getBezierIntersectPt = bezier_intersect.getBezierIntersectPt;
pub const getBezierIntersectPtSlow = bezier_intersect.getBezierIntersectPtSlow;
pub const getBezierTFromPoint = bezier_intersect.getBezierTFromPoint;
pub const getBezierTForXMonotone = bezier_intersect.getBezierTForXMonotone;
pub const bezierAABB = bezier_intersect.bezierAABB;
pub const pointInCurvedPolygon = bezier_intersect.pointInCurvedPolygon;

// ── matrix2d ──────────────────────────────────────────────────────────
pub const srtc2dMatrix = matrix2d.srtc2dMatrix;
pub const srt2dMatrix = matrix2d.srt2dMatrix;
pub const st2dMatrix = matrix2d.st2dMatrix;
pub const rt2dMatrix = matrix2d.rt2dMatrix;
pub const t2dMatrix = matrix2d.t2dMatrix;
pub const src2dMatrix = matrix2d.src2dMatrix;
pub const sr2dMatrix = matrix2d.sr2dMatrix;
pub const s2dMatrix = matrix2d.s2dMatrix;
pub const r2dMatrix = matrix2d.r2dMatrix;
pub const srt2dMatrix2 = matrix2d.srt2dMatrix2;
pub const sr2dMatrix2 = matrix2d.sr2dMatrix2;

// ── triangle ──────────────────────────────────────────────────────────
pub const pointInTriangle = triangle.pointInTriangle;

// ── mirror ────────────────────────────────────────────────────────────
pub const xyMirrorPoint = mirror.xyMirrorPoint;
pub const oppPolyOrientation = mirror.oppPolyOrientation;

// ── path_template ─────────────────────────────────────────────────────
pub const circleCubicInit = path_template.circleCubicInit;
pub const rectLineInit = path_template.rectLineInit;
pub const roundRectLineInit = path_template.roundRectLineInit;
pub const ellipseCubicInit = path_template.ellipseCubicInit;

// ── triangulation ──────────────────────────────────────────────────────
pub const triangulation = @import("triangulation.zig");
pub const trianguatePolygons = triangulation.trianguatePolygons;
pub const TrianguateError = triangulation.TrianguateError;

// ── geometry (SVG/rasterizer ShapeNode/Shapes) ─────────────────────────
pub const geometry = @import("geometry.zig");
pub const svg = @import("svg.zig");
pub const rasterizer = @import("rasterizer.zig");

// ── geometry re-export ────────────────────────────────────────────────
pub const ShapeNode = geometry.ShapeNode;
pub const Shapes = geometry.Shapes;
pub const ShapeError = geometry.ShapeError;
pub const ShapeVertex2d = geometry.ShapeVertex2d;
pub const ShapeVertexFlag = geometry.ShapeVertexFlag;
pub const RawShape = geometry.RawShape;
pub const CurveType = geometry.CurveType;
pub const CurveStructFloat = geometry.CurveStructFloat;
pub const isHoleContour = geometry.isHoleContour;
pub const reverseShapeCloseCurve = geometry.reverseShapeCloseCurve;
pub const rawShapeFree = geometry.rawShapeFree;
pub const rawShapeComputeRect = geometry.rawShapeComputeRect;
pub const rawShapeUpdateRect = geometry.rawShapeUpdateRect;
pub const rawShapeClone = geometry.rawShapeClone;
pub const getCubicCurveType = geometry.getCubicCurveType;
pub const shapesComputePolygon = geometry.shapesComputePolygon;
pub const polyTransformMatrix = geometry.polyTransformMatrix;

// ── svg re-export ─────────────────────────────────────────────────────
pub const SvgParser = svg.SvgParser;
pub const SvgError = svg.SvgError;
pub const initParse = svg.initParse;

// ── rasterizer re-export ──────────────────────────────────────────────
pub const RasterizedPixels = rasterizer.RasterizedPixels;
pub const PixelFormat = rasterizer.PixelFormat;
pub const RasterizerError = rasterizer.RasterizerError;
pub const shapesToPixels = rasterizer.shapesToPixels;
pub const rasterizedPixelsFree = rasterizer.rasterizedPixelsFree;

test {
    _ = rect;
    _ = area;
    _ = polygon;
    _ = lines;
    _ = circle;
    _ = bezier;
    _ = bezier_intersect;
    _ = matrix2d;
    _ = triangle;
    _ = mirror;
    _ = point_in;
    _ = path_template;
    _ = triangulation;
    _ = geometry;
    _ = svg;
    _ = rasterizer;
}
