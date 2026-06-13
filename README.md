# geometry2

Odin `Odin/shared/geometry`의 1:1 Zig 0.16 포팅. `linalg`, `triangulation`, `geometry`, `svg`, `rasterizer` 모듈을 제공.

**마지막 업데이트**: 2026-06-12 | **모듈 상태**: 17/17 단위 테스트 통과

---

## 빌드

```bash
zig build              # 컴파일 체크
zig build test         # 17/17 단위 테스트
zig build run-test     # "linalg sanity: OK" + main 함수 sanity (svg + rasterizer end-to-end)
zig build check        # alias for zig build test
```

`zig build test`는 linalg 모듈의 `test {}` 블록 17개를 실행한다. 내역:
- linalg 기반 (rect, area, matrix 정확성)
- path_template (circleCubicInit, rectLineInit, roundRectLineInit, ellipseCubicInit)
- triangle (pointInTriangle)
- geometry aggregator (shapesComputePolygon, getCubicCurveType x2, reverseShapeCloseCurve x2)
- bezier_intersect (getBezierIntersectPt 등 6개)

---

## 모듈

`geometry2`는 linalg 모듈을 노출하며, 다음 16개 서브모듈을 re-export:

| 서브모듈 | 줄 수 | 설명 |
|---|---:|---|
| linalg.zig | 348 | Vec2/Vec3/Vec4/Mat4x4 기본 타입 + epsilon + vec2Lerp 등 |
| rect.zig | 234 | Rect(T) + 12개 Rect 연산 (rectAnd, rectOr 등) |
| area.zig | 101 | Area(T) + AreaMulMatrix + AreaPointIn |
| polygon.zig | 154 | PointInPolygon, PolygonSignedArea, LineInPolygon, PolygonOverlapsPolygon |
| lines.zig | 290 | LinesIntersect2/3, GetAngle, InCircleTest, SubdivLine/Quadratic/Cubic |
| circle.zig | 19 | Circle(T) |
| bezier.zig | 144 | BezierKind, evalBezier, evalBezierTangent, evalBezierSegment, CvtQuadraticToCubic |
| matrix2d.zig | 140 | srtc2dMatrix, srt2dMatrix, sr2dMatrix, t2dMatrix, srt2dMatrix2 등 11개 함수 |
| triangle.zig | 47 | pointInTriangle |
| mirror.zig | 28 | xyMirrorPoint, oppPolyOrientation |
| point_in.zig | 6 | polygon + triangle + rect + circle re-export aggregator |
| path_template.zig | 217 | CircleCubicInit, RectLineInit, RoundRectLineInit, EllipseCubicInit |
| bezier_intersect.zig | 1095 | GetBezierIntersectPt, GetBezierIntersectPtSlow, GetBezierTFromPoint, BezierAABB, PointInCurvedPolygon + 6개 테스트 |
| triangulation.zig | 297 | C-ABI libtess2 래퍼. TrianguatePolygons + TrianguateError |
| geometry.zig | 1274 | ShapeNode/Shapes/IsHoleContour/ReverseShapeCloseCurve/ShapesComputePolygon/getCubicCurveType/polyTransformMatrix + clipper stub |
| svg.zig | 613 | SvgParser + initParse/deinit + plutovg c-abi + zig-xml streaming pull parser |
| rasterizer.zig | 220 | shapesToPixels + rasterizedPixelsFree + plutovg c-abi |

`geometry2` 최상위 진입점(`src/root.zig`)은 `linalg`, `triangulation`, `geometry`, `svg`, `rasterizer`를 재노출한다.

---

## 사용 예시

```zig
const std = @import("std");
const linalg = @import("geometry2").linalg;
const triangulation = @import("geometry2").triangulation;

// Rect
const r = linalg.rectInit(f32, 0, 100, 0, 100);

// PointInPolygon
const poly = [_]linalg.Vec2(f32){
    .{ .x = 0, .y = 0 },
    .{ .x = 10, .y = 0 },
    .{ .x = 10, .y = 10 },
    .{ .x = 0, .y = 10 },
};
const inside = linalg.pointInPolygon(f32, .{ .x = 5, .y = 5 }, &poly);

// 삼각 측량
const allocator = std.heap.page_allocator;
const polys = [_][]const linalg.Vec2(f32){ &poly };
const indices = try triangulation.trianguatePolygons(&polys, allocator, 0);

// SVG 파싱
const svg_text = "<svg>...</svg>";
var parser = try linalg.svg.initParse(svg_text, allocator);
defer parser.deinit();

// 래스터화
const pixels = try linalg.rasterizer.shapesToPixels(parser.shapes, 100, 100, allocator);
defer linalg.rasterizer.rasterizedPixelsFree(@constCast(&pixels));
```

---

## engine2 통합

`engine2`는 geometry2를 Zig 패키지 의존성으로 사용한다.

```zon
// engine2/build.zig.zon
.dependencies = .{
    .geometry2 = .{
        .path = "../geometry2",
    },
},
```

```zig
// engine2/build.zig
const geometry2_dep = b.dependency("geometry2", .{
    .target = target,
    .optimize = optimize,
});
const geometry_mod = geometry2_dep.module("geometry2");
engine_mod.addImport("geometry", geometry_mod);
```

```zig
// engine2 외부 사용자
const engine2 = @import("engine2");
const linalg = engine2.geometry.linalg;
const triangulation = engine2.geometry.triangulation;
const svg = engine2.geometry.svg;
const rasterizer = engine2.geometry.rasterizer;
```

---

## 외부 의존성

| 의존성 | 종류 | 버전 | 위치 |
|---|---|---|---|
| libtess2 (memononen) | C 라이브러리 | v1.0.2-34-g8dbd648 | `deps/libtess2/` (submodule) |
| plutovg (sammycage) | C 라이브러리 | v1.3.3-12-gdd73459 | `deps/plutovg/` (submodule) |
| zig-xml (ianprime0509) | Zig 0.16 패키지 | 0.2.0 | `build.zig.zon` `.dependencies.xml` |

**zig-xml 선택 이유**: `nektro/zig-xml` 원본은 zigmod 기반이라 nio/tracer/extras 의존성 때문에 Zig 표준 패키지 시스템과 직접 호환되지 않는다. `ianprime0509/zig-xml`은 Zig 0.16 호환 fork로 외부 의존성 없이 standalone 사용 가능.

빌드 시 C 소스는 `addCSourceFiles`로 포함되며, `addIncludePath`는 `b.path(...)`로 절대 경로 변환 필수 (dependency로 사용될 때 상대 경로가 깨지는 문제 방지).

---

## clipper (future)

`Odin/shared/geometry/clipper/clipper.odin` (4214줄) 미포팅. `geometry.zig`에 `__ClipperError` enum stub만 정의:

```zig
/// Odin `clipper.__ClipperError` 1:1 stub. clipper 모듈은 future.
pub const __ClipperError = error{ Failed, TooSmall, LengthMismatch };
```

`ShapeError` error set에 포함됨. `clipper.RectClip` 호출은 양쪽 모두 주석 처리.

---

## 명세

- **1:1 포팅 표** (70개 항목 + 38개 bezier_intersect + triangulation/trianguatePolygons + geometry aggregator + svg + rasterizer): `engine2/ENGINE_REFERENCE.md`의 섹션 3 참조.
- **의미 변경 요약** (Odin union → Zig error set, ArrayList API, Y-flip 등): 동 문서 섹션 6 참조.
- **빌드 그래프** (모듈 의존성, C 소스 포함 관계): 동 문서 섹션 8 참조.

---

## 라이선스 / 저작권

geometry2는 다음 라이브러리를 통합하며, 각각의 라이선스를 따른다:

- **libtess2** — SGI FREE SOFTWARE LICENSE B Version 2.0 (`deps/libtess2/LICENSE.txt`)
- **plutovg** — MIT (`deps/plutovg/LICENSE`)
- **zig-xml (ianprime0509)** — MPL-2.0 (zig-xml 저장소 LICENSE 참조)
- **Odin `shared/geometry`** — Boost Software License 1.0 (Odin LICENSE 참조)

geometry2 자체는 Odin 정본의 Zig 포팅으로, 원본 라이선스를 따른다.
