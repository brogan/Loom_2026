## Global Instructions
- see the following file for a description of this project - A Scala algorithmic drawing application called 'Loom': tutorail/Loom 2022/Loom 2022.md
- while you are reading through check that the details correspond to the actual code implementation in src directory.  Identify any discrepancies with suggestions to amed the md file.  Write this to this file (CLAUDE.md) under a section heading entitled 'Documentation Discrepancies'
- then provide an overall description of the architecture of the project and include than in this file in a section entitled 'Architecture'.
- My aim is to add xml serialisation to this program as will as a JavaFX GUI.
- can you please provide an overall plan of how to proceed in this file (under the heading 'Plan')

## Documentation Discrepancies

### Path References
1. **Tutorial File Path**: The documentation references `tutorail/Loom 2022/Loom 2022.md` but the actual path is `tutorial/Loom 2022/Loom 2022.md` (typo: "tutorail" should be "tutorial").

### Directory Structure Discrepancies
1. **Lib Directory**: Documentation mentions "various libraries that Loom needs. THe most important are the scala libraries" but the actual `lib/` directory contains:
   - `Easing.jar`, `RXTXcomm.jar`, `akka-actor.jar`
   - Serial communication libraries (`librxtxSerial.*`)
   - No explicit Scala libraries (these are managed by SBT as dependencies)

2. **MySketch Location**: Documentation states "MySketch.scala contained in 'mysketch' directory of `src/main/scala/org/loom`" but there are actually two locations:
   - `src/main/scala/org/loom/mysketch/MySketch.scala` (main implementation)
   - `sketches/Subdivide/MySketch.scala` (sketch-specific implementation)

3. **Resources Structure**: Documentation mentions `resources/polygonSets` but the actual structure is:
   - `sketches/Subdivide/resources/shapes/polygonSet/`
   - Not `resources/polygonSets` as documented

### Code vs Documentation Inconsistencies
1. **Scala Version**: The project now uses Scala 3.7.3 (as per build.sbt) but documentation doesn't mention version requirements.

2. **XML Loading**: Documentation mentions DTD issues with XML files, but the actual implementation uses `scala-xml` library for parsing.

3. **Build System**: Documentation references SBT but doesn't mention the current dependency structure:
   - `scala-swing` for GUI components
   - `scala-xml` for XML processing
   - Modern SBT build configuration

4. **Configuration Location**: Documentation mentions `confi_default.xml` (typo) but actual file is `config_default.xml`.

### Suggested Updates to Documentation
1. Fix typo: "tutorail" → "tutorial"
2. Fix typo: "confi_default.xml" → "config_default.xml"
3. Update library description to reflect SBT dependency management
4. Clarify the dual MySketch structure (main vs sketch-specific)
5. Update resource directory paths to reflect actual structure
6. Add Scala version requirements
7. Update XML processing details for Scala 3 compatibility

## Architecture

### High-Level Architecture
Loom is a Scala-based algorithmic drawing application built around a modular architecture centered on polygonal subdivision and rendering. The system follows a layered design:

#### Core Components

**1. Geometry Layer** (`org.loom.geometry`)
- **Vector2D/Vector3D**: Basic geometric primitives for 2D/3D coordinates
- **Polygon2D/Polygon3D**: Polygon representations supporting both line and spline-based geometry
- **Shape2D/Shape3D**: Collections of polygons that can be subdivided and transformed
- **PolygonSet/PolygonSetCollection**: Management of polygon collections loaded from XML
- **Subdivision**: Core subdivision algorithms (QUAD, TRI) with recursive processing

**2. Scene Management** (`org.loom.scene`)
- **Sprite2D/Sprite3D**: Renderable instances of shapes with position, animation, and rendering properties
- **Scene**: Container for managing multiple sprites
- **Camera/View**: 3D perspective and view management
- **Animator2D/Animator3D**: Animation parameter management

**3. Rendering System** (`org.loom.scene`)
- **Renderer**: Individual rendering configurations (stroke, fill, points, etc.)
- **RendererSet**: Collections of renderers with selection logic
- **RendererSetLibrary**: Library of renderer sets
- **RenderTransform**: Dynamic parameter modification during rendering

**4. Transformation System** (`org.loom.transform`)
- **Transform**: Abstract base for point/polygon transformations
- **AnchorsLinkedToCentre**: Specific transformation for anchor points
- **CentralAnchors**: Central point transformations
- **ExteriorAnchors**: External point transformations
- **InnerControlPoints/OuterControlPoints**: Spline control point transformations

**5. Media & I/O** (`org.loom.media`)
- **PolygonSetLoader**: XML-based shape loading
- **ImageLoader/ImageWriter**: Image handling for captures
- **SoundManager**: Audio support
- **TextReaderWriter**: Text file operations

**6. Application Scaffold** (`org.loom.scaffold`)
- **Main**: Application entry point
- **Config**: XML configuration parsing
- **Sketch**: Abstract base class for drawing applications
- **DrawFrame/DrawPanel**: Swing-based display system
- **Display/DrawManager**: Screen rendering management

**7. Interaction** (`org.loom.interaction`)
- **KeyPressListener/MouseClick/MouseMotion**: Input handling
- **SerialListener**: Hardware communication support

**8. Utilities** (`org.loom.utility`)
- **Range/RangeXY**: Parameter range definitions
- **Colors/Palette**: Color management
- **Transform2D/Transform3D**: Geometric transformations
- **Randomise**: Random value generation

#### Data Flow Architecture
1. **Configuration**: XML config files define sketch parameters
2. **Shape Loading**: XML polygon sets loaded via PolygonSetLoader
3. **Shape Creation**: Polygon sets converted to Shape2D/3D objects
4. **Subdivision**: Recursive subdivision applied based on SubdivisionParams
5. **Sprite Instantiation**: Shapes become positioned, animated sprites
6. **Scene Assembly**: Sprites added to scene with camera/view setup
7. **Rendering Loop**: Continuous update/draw cycle with renderer application
8. **Output**: Screen display and optional image capture

#### Plugin Architecture
- **Transform System**: Modular transformation plugins (AnchorsLinkedToCentre, etc.)
- **Subdivision Modes**: Pluggable subdivision algorithms (SplineQuad, SplineTri)
- **Renderer System**: Hierarchical rendering configuration

#### Sketch System
The application supports multiple "sketches" (different drawing applications):
- Each sketch has its own directory under `sketches/`
- MySketch implementations provide sketch-specific logic
- Shared core library in `src/main/scala/org/loom/`

## Plan

### Phase 1: XML Serialization Implementation

#### 1.1 Core Serialization Infrastructure
- **Create XML serialization traits/interfaces**
  - `XMLSerializable` trait with `toXML` and `fromXML` methods
  - `XMLSerializer` utility object for common operations

#### 1.2 Geometry Serialization
- **Implement XML serialization for core geometry classes:**
  - Vector2D/Vector3D → Simple coordinate XML elements
  - Polygon2D/Polygon3D → Polygon definition with points
  - Shape2D/Shape3D → Shape collections with metadata
  - PolygonSet/PolygonSetCollection → Enhanced current XML format

#### 1.3 Configuration & Parameters Serialization
- **Extend existing config system:**
  - SubdivisionParams → Full parameter set serialization
  - SubdivisionParamsSet/Collection → Parameter collections
  - Renderer/RendererSet/Library → Complete rendering setup
  - Transform parameters → All transformation settings

#### 1.4 Scene & Animation Serialization
- **Implement scene state serialization:**
  - Sprite2D/Sprite3D → Position, animation, rendering state
  - Scene → Complete scene with all sprites
  - Animator2D/Animator3D → Animation parameters
  - Camera/View → 3D viewing configuration

### Phase 2: JavaFX GUI Development

#### 2.1 GUI Architecture Design
- **Replace Swing with JavaFX:**
  - Create JavaFX Application class extending `javafx.application.Application`
  - Implement JavaFX-based canvas for drawing output
  - Design main window layout with menu, toolbar, parameter panels

#### 2.2 Parameter Control Panels
- **Create UI for subdivision parameters:**
  - Subdivision type selection (QUAD/TRI)
  - Probability sliders and numeric inputs
  - Transform parameter controls with real-time preview
  - Rendering parameter panels (stroke, fill, animation)

#### 2.3 Shape Management Interface
- **File operations and shape library:**
  - File menu (New, Open, Save, Export)
  - Shape library browser for XML polygon sets
  - Drag-and-drop shape loading
  - Thumbnail preview of available shapes

#### 2.4 Real-time Preview System
- **Interactive editing:**
  - Live parameter adjustment with immediate visual feedback
  - Canvas zoom/pan functionality
  - Animation playback controls
  - Render quality settings

### Phase 3: Integration & Enhancement

#### 3.1 XML-GUI Integration
- **Connect serialization with GUI:**
  - Save/Load complete project state (shapes + parameters + scene)
  - Import/Export individual components
  - Preset management system
  - Undo/Redo functionality using XML snapshots

#### 3.2 Enhanced Shape Creation
- **Built-in shape editor:**
  - JavaFX-based bezier curve editor
  - Replace external "Bezier Draw" dependency
  - Direct spline manipulation in GUI
  - Shape validation and optimization

#### 3.3 Advanced Features
- **Professional workflow features:**
  - Batch processing multiple shapes
  - Animation timeline editor
  - High-resolution export options
  - Plugin system for custom transformations

### Phase 4: Migration & Modernization

#### 4.1 Scala 3 Optimization
- **Leverage Scala 3 features:**
  - Use enums for constants (Renderer modes, subdivision types)
  - Implement using clauses for context parameters
  - Apply opaque types for type safety
  - Utilize union types where appropriate

#### 4.2 Performance Optimization
- **Improve rendering performance:**
  - Parallel processing for subdivision calculations
  - Efficient data structures for large polygon sets
  - Memory optimization for high-resolution rendering
  - GPU acceleration consideration for future

#### 4.3 Testing & Documentation
- **Quality assurance:**
  - Unit tests for core algorithms
  - Integration tests for XML serialization
  - GUI automated testing with TestFX
  - Updated comprehensive documentation

### Implementation Priority
1. **XML Serialization** (Foundation for data persistence)
2. **Basic JavaFX GUI** (Modern user interface)
3. **Parameter Controls** (Essential user interaction)
4. **Integration** (Complete workflow)
5. **Advanced Features** (Professional polish)

## Implementation Timeline & Strategy

### Realistic Time Estimate
**Total Development Time: 70-145 hours**
- Phase 1 (XML Serialization): 15-30 hours
- Phase 2 (JavaFX GUI): 40-80 hours (largest component)
- Phase 3 (Integration): 10-20 hours
- Phase 4 (Optimization): 10-15 hours

### Claude Pro Constraints
- **5 hours usage/month** ≈ 100-150 focused messages
- **Estimated Timeline: 12-24 months** working within Claude Pro limits
- **Key Limitation**: I cannot run/test code, only write and review it

### How You Can Maximize Efficiency

#### 1. Preparation Strategy
**Before Each Session:**
- Have SBT running and project loaded in your IDE
- Identify specific files/features to work on
- Prepare any error messages or issues from previous work
- Have test data/XML files ready

#### 2. Focused Work Sessions
**Target 2-3 hour focused blocks:**
- **Session Goal**: Complete one specific component (e.g., "Vector2D XML serialization")
- **Immediate Testing**: Run code after each change I provide
- **Quick Feedback Loop**: Report compilation errors immediately
- **Iterative Refinement**: Fix issues in the same session

#### 3. Strategic Implementation Order
**Start with High-Impact, Low-Risk items:**

**Month 1-2: XML Serialization Foundation**
- Vector2D/Vector3D serialization (simple, testable)
- Basic Polygon2D serialization
- Configuration serialization (extends existing system)

**Month 3-4: Core Geometry Serialization**
- Complete Polygon2D/3D serialization
- Shape2D/3D serialization
- PolygonSet serialization

**Month 5-8: Basic JavaFX GUI**
- Simple JavaFX window with canvas
- Basic file operations (open/save XML)
- Simple parameter controls

**Month 9-12+: Integration & Advanced Features**

#### 4. Testing Strategy
**Your Critical Role:**
- **Immediate Compilation Testing**: Check every code change compiles
- **Runtime Testing**: Run the application after significant changes
- **Integration Testing**: Ensure new features work with existing code
- **Performance Testing**: Monitor rendering performance

#### 5. Efficient Communication
**Maximize Each Message:**
- **Specific Requests**: "Implement XML serialization for Vector2D class"
- **Include Context**: Show compilation errors, runtime exceptions
- **Batch Related Changes**: Group similar modifications together
- **Prioritize Blockers**: Address compilation/runtime errors first

#### 6. Development Environment Setup
**Optimize for Speed:**
- Use IDE with good Scala 3 support (IntelliJ IDEA or VS Code with Metals)
- Set up automatic compilation on save
- Configure hot-reload if possible
- Have multiple terminal windows ready (SBT, testing, file operations)

#### 7. Risk Mitigation
**Version Control Strategy:**
- **Git branch for each phase**: `xml-serialization`, `javafx-gui`, etc.
- **Commit after each working session**: Preserve progress
- **Tag stable versions**: Easy rollback points

#### 8. Parallel Work Opportunities
**While waiting for next Claude session:**
- Study JavaFX documentation and examples
- Prepare test XML files and data
- Research JavaFX-Scala integration patterns
- Set up JavaFX dependencies in build.sbt
- Create mockup/wireframes for GUI layout

### Most Efficient Starting Point
**Recommended First Session (90 minutes):**
1. Create `XMLSerializable` trait (15 min)
2. Implement Vector2D XML serialization (30 min)
3. Create simple test to verify it works (15 min)
4. Fix any compilation issues (30 min)

**Success Criteria:** Working XML serialization for Vector2D with unit test

This establishes the pattern and foundation for all subsequent serialization work, proving the approach before scaling to more complex classes.



