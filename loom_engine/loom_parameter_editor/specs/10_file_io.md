# File I/O — XML Serialisation

All I/O classes live in `loom_parameter_editor/file_io/`. Every class provides `load(file_path) → Model` and `save(model, file_path)` class methods. The XML library used throughout is **lxml** (`etree`).

---

## `file_io/project_io.py` — `ProjectIO`

Root element: `<LoomProject version="1.0">`

```xml
<LoomProject version="1.0">
  <Name>MyProject</Name>
  <Description/>
  <Created>2025-04-01T10:00:00</Created>
  <Modified>2025-04-01T10:00:00</Modified>
  <Files>
    <File domain="global"      path="configuration/global_config.xml"/>
    <File domain="rendering"   path="configuration/rendering.xml"/>
    <!-- … -->
  </Files>
</LoomProject>
```

Datetime format: `%Y-%m-%dT%H:%M:%S`

---

## `file_io/global_config_io.py` — `GlobalConfigIO`

Root element: `<GlobalConfig>`

Color serialised as attributes: `<BorderColor r="0" g="0" b="0" a="255"/>`

Boolean values: `"true"` / `"false"` strings.

```xml
<GlobalConfig>
  <Name>MyProject</Name>
  <Note/>
  <Width>1080</Width>
  <Height>1080</Height>
  <QualityMultiple>1</QualityMultiple>
  <ScaleImage>false</ScaleImage>
  <Animating>false</Animating>
  <DrawBackgroundOnce>true</DrawBackgroundOnce>
  <Subdividing>true</Subdividing>
  <Fullscreen>false</Fullscreen>
  <BorderColor r="0" g="0" b="0" a="255"/>
  <BackgroundColor r="255" g="255" b="255" a="255"/>
  <OverlayColor r="0" g="0" b="0" a="170"/>
  <BackgroundImagePath/>
  <ThreeD>false</ThreeD>
  <CameraViewAngle>120</CameraViewAngle>
  <Serial>false</Serial>
  <Port>/dev/ttyUSB0</Port>
  <Mode>bytes</Mode>
  <Quantity>4</Quantity>
</GlobalConfig>
```

---

## `file_io/rendering_io.py` — `RenderingIO`

Root element: `<RendererSetLibrary name="MainLibrary">`

```xml
<RendererSetLibrary name="MainLibrary">
  <RendererSet name="default" enabled="true" playbackMode="STATIC" changeFrequency="1">
    <Renderer name="fill" enabled="true" mode="FILLED" strokeWidth="1.0"
              strokeColor="0,0,0,255" fillColor="255,255,255,255"
              pointSize="2.0" holdLength="1" pointStroked="true" pointFilled="true">
      <StrokeWidthChange enabled="false" kind="SEQ" motion="UP" cycle="CONSTANT"
                         scale="POLY" min="0.0" max="1.0" increment="0.1" pauseMax="0">
        <SizePalette/>
      </StrokeWidthChange>
      <StrokeColorChange enabled="false" kind="SEQ" motion="UP" cycle="CONSTANT"
                         scale="POLY" pauseMax="0" pauseChannel="GREEN">
        <MinColor r="0" g="0" b="0" a="255"/>
        <MaxColor r="255" g="255" b="255" a="255"/>
        <Increment r="1" g="1" b="1" a="1"/>
        <PauseColorMin r="0" g="0" b="0" a="255"/>
        <PauseColorMax r="0" g="0" b="0" a="255"/>
        <Palette/>
      </StrokeColorChange>
      <FillColorChange enabled="false" …> … </FillColorChange>
      <PointSizeChange enabled="false" …> … </PointSizeChange>
      <!-- BrushConfig present only for BRUSHED mode -->
      <!-- StencilConfig present only for STAMPED mode -->
    </Renderer>
  </RendererSet>
</RendererSetLibrary>
```

### BrushConfig XML

```xml
<BrushConfig drawMode="FULL_PATH" stampSpacing="4.0" spacingEasing="LINEAR"
             followTangent="true" perpJitterMin="-2.0" perpJitterMax="2.0"
             scaleMin="0.8" scaleMax="1.2" opacityMin="0.6" opacityMax="1.0"
             stampsPerFrame="10" agentCount="1" postCompletionMode="HOLD"
             blurRadius="0" pressureSizeInfluence="0.0" pressureAlphaInfluence="0.0">
  <Brushes>
    <Brush name="brush01.png" enabled="true"/>
  </Brushes>
  <Meander enabled="false" amplitude="8.0" frequency="0.03" samples="24" seed="0"
           animated="false" animSpeed="0.01" scaleAlongPath="false"
           scaleAlongPathFrequency="0.05" scaleAlongPathRange="0.4"/>
</BrushConfig>
```

### StencilConfig XML

```xml
<StencilConfig drawMode="FULL_PATH" stampSpacing="4.0" spacingEasing="LINEAR"
               followTangent="true" perpJitterMin="-2.0" perpJitterMax="2.0"
               scaleMin="0.8" scaleMax="1.2" stampsPerFrame="10" agentCount="1"
               postCompletionMode="HOLD">
  <Stencils>
    <Stencil name="stencil01.png" enabled="true"/>
  </Stencils>
  <OpacityChange enabled="false" …/>
</StencilConfig>
```

---

## `file_io/polygon_config_io.py` — `PolygonConfigIO`

Root element: `<PolygonSetLibrary name="MainLibrary">`

```xml
<PolygonSetLibrary name="MainLibrary">
  <PolygonSet name="MyShape" file="myshape.poly.xml" enabled="true"/>
</PolygonSetLibrary>
```

This file records only the registry (name + filename). The geometry data itself lives in the referenced `.poly.xml` files under `polygonSets/`.

---

## `file_io/subdivision_config_io.py` — `SubdivisionConfigIO`

Root element: `<SubdivisionParamsSetCollection>`

```xml
<SubdivisionParamsSetCollection>
  <SubdivisionParamsSet name="default">
    <SubdivisionParams name="simpler" enabled="true"
                       type="QUAD" visibilityRule="ALL"
                       ranMiddle="false" ranDiv="100.0"
                       lineRatioX="0.5" lineRatioY="0.5"
                       controlPointRatioX="0.25" controlPointRatioY="0.75"
                       continuous="true"
                       polysTransform="true" polysTransformWhole="false"
                       ptwProbability="100.0"
                       ptwRandomTranslation="false" ptwRandomScale="false"
                       ptwRandomRotation="false" ptwCommonCentre="false"
                       ptwRandomCentreDivisor="100.0"
                       polysTransformPoints="false" ptpProbability="100.0">
      <InsetTransform>
        <Translation x="0.0" y="0.0"/>
        <Scale x="0.5" y="0.5"/>
        <Rotation x="0.0" y="0.0"/>
      </InsetTransform>
      <PtwTransform>
        <Translation x="0.0" y="0.0"/>
        <Scale x="1.0" y="1.0"/>
        <Rotation x="0.0" y="0.0"/>
      </PtwTransform>
      <PtwRandomTranslationRange xMin="0.0" xMax="0.0" yMin="0.0" yMax="0.0"/>
      <PtwRandomScaleRange xMin="1.0" xMax="1.0" yMin="1.0" yMax="1.0"/>
      <PtwRandomRotationRange min="0.0" max="0.0"/>
      <TransformSet>
        <!-- Optional transform entries -->
        <ExteriorAnchors name="ExteriorAnchors" rangeMin="0.0" rangeMax="0.0"/>
        <CentralAnchors name="CentralAnchors" rangeMin="0.0" rangeMax="0.0"/>
        <AnchorsLinkedToCentre name="AnchorsLinkedToCentre" rangeMin="0.0" rangeMax="0.0"/>
        <OuterControlPoints name="OuterControlPoints" rangeMin="0.0" rangeMax="0.0"/>
        <InnerControlPoints name="InnerControlPoints" rangeMin="0.0" rangeMax="0.0"/>
      </TransformSet>
    </SubdivisionParams>
  </SubdivisionParamsSet>
</SubdivisionParamsSetCollection>
```

---

## `file_io/sprite_config_io.py` — `SpriteConfigIO`

Root element: `<SpriteLibrary name="MainLibrary">`

```xml
<SpriteLibrary name="MainLibrary">
  <SpriteSet name="default">
    <Sprite name="sprite1" enabled="true"
            geoSourceType="POLYGON_SET" geoPolygonSetName="MyShape"
            geoSubdivisionParamsSetName="default"
            geoShape3DType="NONE" geoShape3DParam1="4" geoShape3DParam2="4" geoShape3DParam3="4"
            geoRegularPolygonSides="4"
            shapeSetName="default" shapeName="sprite1"
            rendererSetName="default"
            animatorType="random">
      <Params locationX="540.0" locationY="540.0"
              sizeX="1.0" sizeY="1.0" startRotation="0.0"
              animationEnabled="true" totalDraws="0"
              translationRangeXMin="0.0" translationRangeXMax="0.0"
              translationRangeYMin="0.0" translationRangeYMax="0.0"
              scaleRangeXMin="0.0" scaleRangeXMax="0.0"
              scaleRangeYMin="0.0" scaleRangeYMax="0.0"
              rotationRangeMin="0.0" rotationRangeMax="0.0"
              rotOffsetX="0.0" rotOffsetY="0.0"
              scaleFactorX="1.0" scaleFactorY="1.0"
              rotationFactor="0.0"
              speedFactorX="0.0" speedFactorY="0.0"
              jitter="false" loopMode="NONE"
              morphMin="0.0" morphMax="1.0"/>
      <GeoInlinePoints/>
      <Keyframes/>
      <MorphTargets/>
    </Sprite>
  </SpriteSet>
</SpriteLibrary>
```

### `auto_generate_shapes_xml(sprite_lib, path)`

Writes `shapes.xml` in the legacy Scala format consumed by `org.loom.scaffold.Config`. One `<Shape>` per `SpriteDef`, using `shapeSetName`/`shapeName` (auto-derived from `SpriteSet.name`/`SpriteDef.name`).

### `migrate_shapes_into_sprites(shapes_path, sprite_library)`

On project open, reads a legacy `shapes.xml` and patches `geo_*` fields into existing `SpriteDef` records where they are missing/empty. Used for backward-compatibility with projects created before the sprites-first model was introduced.

---

## `file_io/open_curve_config_io.py` — `OpenCurveConfigIO`

Root element: `<OpenCurveSetLibrary name="MainLibrary">`

```xml
<OpenCurveSetLibrary name="MainLibrary">
  <OpenCurveSet name="MyCurve" file="mycurve.curve.xml" enabled="true"/>
</OpenCurveSetLibrary>
```

---

## `file_io/point_config_io.py` — `PointConfigIO`

Root element: `<PointSetLibrary name="MainLibrary">`

```xml
<PointSetLibrary name="MainLibrary">
  <PointSet name="MyPoints" file="mypoints.points.xml" enabled="true">
    <Points>
      <Point x="100.0" y="200.0"/>
    </Points>
  </PointSet>
</PointSetLibrary>
```

For file-backed point sets the `<Points>` element is omitted or empty; point data lives in the external file.

---

## `file_io/oval_config_io.py` — `OvalConfigIO`

Root element: `<OvalSetLibrary name="MainLibrary">`

```xml
<OvalSetLibrary name="MainLibrary">
  <OvalSet name="MyOval" enabled="true" width="200.0" height="100.0" segments="64"/>
</OvalSetLibrary>
```

---

## `file_io/regular_polygon_io.py` — `RegularPolygonIO`

Writes editor-only regular polygon data to `regularPolygons/<name>.xml`. Not read by the engine; used to persist the editor's representation of regular n-gon polygon sets so they survive project re-opens.

---

## `file_io/palette_io.py` — `PaletteIO`

Reads and writes colour palettes as JSON arrays to `palettes/`. Each palette is a list of `[r, g, b, a]` arrays.

```json
[[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255]]
```

Used by `PaletteEditorWidget` when loading/saving named palettes.

---

## `file_io/shape_config_io.py` — `ShapeConfigIO`

Reads/writes the legacy `shapes.xml` format. In the current editor this is a read-legacy / write-compat path only; the canonical data lives in `sprites.xml`.

---

## Common Patterns

### Boolean encoding
All booleans are stored as lowercase strings: `"true"` / `"false"`.

### Enum encoding
Enums are stored by name (`.name` attribute): e.g., `"QUAD"`, `"STROKED"`, `"NUM_SEQ"`.  
Backward-compat aliases: `PAL_SEQ` → `SEQ`, `PAL_RAN` → `RAN` handled in `ChangeKind.from_string()`.

### Color encoding
Colors are stored as RGBA attribute tuples on a self-closing element:
```xml
<StrokeColor r="0" g="0" b="0" a="255"/>
```
or as comma-separated string attributes on the renderer element:
```xml
strokeColor="0,0,0,255"
```
(The rendering IO uses the latter form for compactness on `<Renderer>` attributes.)

### File writes
All files are written with `lxml.etree.ElementTree.write(pretty_print=True, xml_declaration=True, encoding="UTF-8")`.

### Error handling
All IO load methods use `try/except` at the field level, falling back to defaults on parse errors, so partially-written or older-format XML files open without crashing.
