# Loom Engine — Interaction and Input System
**Specification 07**  
**Date:** 2026-04-19  
**Depends on:** `01_technical_overview.md`, `05_configuration.md`

---

## 1. Purpose

This document specifies the interaction layer — how user input (keyboard, mouse) and external hardware (serial sensors, RFID) reach the running sketch. It covers:

- `InteractionManager` — the central input dispatcher
- `KeyPressListener` — keyboard input
- `MouseClick` / `MouseMotion` — mouse input
- `Port` / `SerialListener` — serial communication
- Wiring: how `DrawPanel` connects these components
- The camera control model
- Design assessment and Swift migration notes

---

## 2. Component Map

```
DrawPanel
  ├── creates InteractionManager(drawManager)
  ├── registers KeyPressListener(interactionManager)  → addKeyListener()
  ├── registers MouseClick(interactionManager)        → addMouseListener()
  └── registers MouseMotion(interactionManager)       → addMouseMotionListener()

InteractionManager
  ├── holds DrawManager reference (for reload, sketch state access)
  ├── holds Camera reference (for 3D navigation)
  ├── creates Port(self) if Config.serial == true
  └── exposes action methods called by listeners

Port
  └── creates SerialListener(self) → registered with RXTX serial library
```

All files are in `src/main/scala/org/loom/interaction/`.

---

## 3. InteractionManager

**File:** `InteractionManager.scala`

```scala
class InteractionManager(val drawManager: DrawManager) extends JPanel
```

`InteractionManager` is the single point of contact between raw input events and sketch state. Listeners receive OS events, translate them to named actions, and call the corresponding `InteractionManager` method. This keeps key mapping and mouse wiring isolated from the action logic.

### 3.1 State Fields

| Field | Type | Description |
|-------|------|-------------|
| `shiftKey` | `Boolean` | Shift modifier currently held |
| `controlKey` | `Boolean` | Control modifier currently held |
| `mousePressed` | `Boolean` | Mouse button currently down |
| `mouseReleased` | `Boolean` | Mouse button just released |
| `mouseDragged` | `Boolean` | Mouse being dragged |
| `mousePosition` | `Point` | Current mouse cursor coordinates |
| `paused` | `Boolean` | Animation pause state (mirrors sketch.paused) |
| `port` | `Port` | Serial port instance; `null` if `Config.serial == false` |

### 3.2 Camera Navigation

`InteractionManager` provides a 9-DOF camera control model. The exact transform applied depends on which modifier key is held:

| Method | No modifier | Shift | Control |
|--------|-------------|-------|---------|
| `moveLeft()` | Track left (translate X−) | Turn left (yaw−, rotate Y) | Bank left (roll−, rotate Z) |
| `moveRight()` | Track right (translate X+) | Turn right (yaw+, rotate Y) | Bank right (roll+, rotate Z) |
| `moveUp()` | Track forward (translate Z−) | Crane up (translate Y+) | Pitch up (rotate X+) |
| `moveDown()` | Track back (translate Z+) | Crane down (translate Y−) | Pitch down (rotate X−) |

Step sizes are taken from `Camera.translateSpeed` and `Camera.rotateSpeed` singleton constants.

### 3.3 Control Methods

| Method | Effect |
|--------|--------|
| `switchRenderingMode(mode: Int)` | Sets `drawManager.sketch.renderer.mode` to `mode` (POINTS/STROKED/FILLED/FILLED_STROKED) |
| `captureStill()` | Calls `Capture.captureStill()` |
| `captureVideo()` | Calls `Capture.captureVideo()` to toggle video capture |
| `togglePause()` | Flips `paused`; sets `drawManager.sketch.paused` |
| `reload()` | Calls `drawManager.reload()` — re-reads all XML files and reinitialises sketch |
| `quit()` | Closes serial port if open; calls `System.exit(0)` |

### 3.4 Serial Data Routing

Two overloads handle incoming serial data:

```scala
def passToSprite(readings: Array[Int]): Unit
  // Stores readings in drawManager.sketch.serialByteReadings
  // No event notification — sketch polls this array in update()

def passToSprite(reading: String): Unit
  // Stores string in drawManager.sketch.serialStringReading
  // Calls drawManager.sketch.serialEventNotify() — overrideable callback
```

---

## 4. KeyPressListener

**File:** `KeyPressListener.scala`

```scala
class KeyPressListener(val interactionManager: InteractionManager) extends KeyListener
```

### 4.1 Key Map

| Key | Action |
|-----|--------|
| `Shift` | Sets `interactionManager.shiftKey = true` (cleared on release) |
| `Control` | Sets `interactionManager.controlKey = true` (cleared on release) |
| `←` `→` `↑` `↓` | `moveLeft()` / `moveRight()` / `moveUp()` / `moveDown()` |
| `1` | `switchRenderingMode(Renderer.POINTS)` |
| `2` | `switchRenderingMode(Renderer.STROKED)` |
| `3` | `switchRenderingMode(Renderer.FILLED)` |
| `4` | `switchRenderingMode(Renderer.FILLED_STROKED)` |
| `S` | `captureStill()` |
| `V` | `captureVideo()` |
| `P` | `togglePause()` |
| `Q` | `quit()` |
| `F5` | `reload()` |

All mappings are hard-coded (`java.awt.event.KeyEvent` VK constants). There is no runtime remapping.

Key repeat: OS-level key repeat is not suppressed, so holding an arrow key issues continuous `moveLeft()` calls.

---

## 5. MouseClick and MouseMotion

**Files:** `MouseClick.scala`, `MouseMotion.scala`

```scala
class MouseClick(val interactionManager: InteractionManager) extends MouseAdapter
class MouseMotion(val interactionManager: InteractionManager) extends MouseMotionListener
```

### 5.1 MouseClick

| Callback | Effect |
|----------|--------|
| `mousePressed(e)` | Sets `interactionManager.mousePressed = true`; updates `mousePosition` |
| `mouseReleased(e)` | Sets `interactionManager.mouseReleased = true`; updates `mousePosition` |
| `mouseMoved(e)` | No-op (currently disabled) |

### 5.2 MouseMotion

| Callback | Effect |
|----------|--------|
| `mouseDragged(e)` | Sets `interactionManager.mouseDragged = true`; updates `mousePosition`; prints position to stdout |
| `mouseMoved(e)` | No-op (currently disabled) |

Mouse state is stored in `InteractionManager` fields. `MySketch` can read `interactionManager.mousePosition`, `mousePressed`, etc. in its `update()` loop. There is no event callback to `MySketch` — it must poll.

---

## 6. Serial Communication

### 6.1 Port

**File:** `Port.scala`

```scala
class Port(val interactionManager: InteractionManager)
```

Instantiated by `InteractionManager` if `Config.serial == true`. Initialises synchronously in the constructor:
1. Gets `CommPortIdentifier` for `Config.port` path
2. Opens a `SerialPort` at 9600 baud, 8N1
3. Opens input/output streams
4. Registers a `SerialListener` for `DATA_AVAILABLE` events

If the port is unavailable the constructor throws — no recovery path exists.

### 6.2 SerialListener

**File:** `SerialListener.scala`

```scala
class SerialListener(val port: Port) extends SerialPortEventListener

def serialEvent(event: SerialPortEvent): Unit
  // dispatches DATA_AVAILABLE to port.dataAvailable()
```

### 6.3 Data Processing

`Port.dataAvailable()` dispatches based on `Config.mode`:

**`bytes` mode (sensor readings):**
- Expects fixed-length chunks of `Config.quantity` bytes
- First byte must be `−5` (start marker); remainder are sensor values
- Converts signed bytes to ints; passes `Array[Int]` to `interactionManager.passToSprite()`

**`char` mode (button):**
- Takes first byte of the chunk
- Converts to `Char`, then to `String`
- Passes string to `interactionManager.passToSprite()`

**`rfid` mode (RFID reader):**
- Accumulates bytes from first `'F'` character into a `StringBuffer`
- When buffer reaches `Config.quantity` bytes, extracts the RFID substring
- Extracts characters from index `(Config.quantity - 9)` to `Config.quantity`
- Passes extracted string to `interactionManager.passToSprite()`

### 6.4 close()

```scala
def close(): Unit
  // Removes event listener; closes serial port
```

Called by `InteractionManager.quit()`.

---

## 7. Wiring in DrawPanel

**File:** `src/main/scala/org/loom/scaffold/DrawPanel.scala`

`DrawPanel` creates and wires the entire interaction chain in its constructor:

```scala
val drawManager = new DrawManager()
val interactionManager = new InteractionManager(drawManager)

addKeyListener(new KeyPressListener(interactionManager))
addMouseListener(new MouseClick(interactionManager).asInstanceOf[MouseAdapter])
addMouseMotionListener(new MouseMotion(interactionManager).asInstanceOf[MouseMotionListener])

setFocusable(true)
```

The `setFocusable(true)` call is critical — without it, `JPanel` does not receive key events.

### 7.1 Full Event Flow

```
OS input event
    ↓
Java AWT event dispatch thread
    ↓
KeyPressListener / MouseClick / MouseMotion
    ↓
InteractionManager method (moveLeft, togglePause, etc.)
    ↓
Camera state mutation  OR  drawManager.sketch state mutation
    ↓
Next animation frame: scene.update() + scene.draw() sees new state
```

Serial input follows a separate thread path:

```
Serial port hardware event
    ↓
RXTX library thread
    ↓
SerialListener.serialEvent()
    ↓
Port.dataAvailable()  →  Port.processBytes() / processChar() / processRFID()
    ↓
InteractionManager.passToSprite()
    ↓
sketch.serialByteReadings / serialStringReading updated
sketch.serialEventNotify() called (string mode only)
```

---

## 8. MySketch Integration Points

A `MySketch` implementation can respond to input by:

**Polling in `update()`:**
```scala
// Mouse position
val mx = drawManager.interactionManager.mousePosition.x
val my = drawManager.interactionManager.mousePosition.y

// Sensor readings (bytes mode)
val sensorVal = serialByteReadings(0)   // index per sensor channel

// RFID / button (char/rfid mode)
val rfid = serialStringReading
```

**Overriding the RFID callback:**
```scala
override def serialEventNotify(): Unit = {
  // called immediately when a new string arrives via serial
  // serialStringReading is populated before this is called
}
```

There is no equivalent callback for byte-mode serial data or for mouse events — both must be polled.

---

## 9. Design Assessment

### I1 — Serial port failure crashes the application

`Port` initialises the serial port synchronously in its constructor. If `Config.serial == true` and the port path in `Config.port` is unavailable or busy, the constructor throws an unhandled exception that propagates up through `InteractionManager` and crashes the application. There is no graceful degradation.

---

### I2 — Mouse and byte-mode serial require polling; no unified event model

Three input sources behave differently:
- **Keyboard**: synchronous callback via `KeyPressListener`
- **Mouse**: state written to `InteractionManager` fields; sketch must poll
- **Serial string (RFID/char)**: `serialEventNotify()` callback available
- **Serial bytes (sensors)**: no callback; sketch must poll `serialByteReadings`

This inconsistency means `MySketch` must mix callback overrides with polling in `update()`.

---

### I3 — Key bindings are hard-coded and not extensible

All key-to-action mappings are in `KeyPressListener.keyPressed()` as hard-coded VK constants. There is no configuration file, no remapping API, and no way for `MySketch` to intercept or add key bindings without modifying the listener class.

---

### I4 — Mouse state flags are never automatically cleared

`interactionManager.mousePressed` is set to `true` on press and `true` again on release (as `mouseReleased`). Neither flag is cleared between frames. A sketch testing `mousePressed` in `update()` will see `true` for the entire time the button is held plus one additional frame. There is no `mouseClicked` (single-frame) detection.

---

### I5 — Camera speed is a global singleton constant

`Camera.translateSpeed` and `Camera.rotateSpeed` are singleton `val`s. Per-scene or per-sketch camera sensitivity is not possible without modifying the singleton.

---

### I6 — No focus recovery after window deactivation

If the application window loses focus (e.g., switching to another app), modifier key state (`shiftKey`, `controlKey`) is not cleared. On return the camera model may apply wrong transforms until the modifier key is pressed and released again.

---

### I7 — Serial RFID protocol has no validation

The RFID extraction is purely positional: it takes bytes at a fixed offset within the buffer regardless of content. There is no checksum, no start/end marker validation, and no timeout for incomplete messages. A partial transmission will produce a garbled RFID string.

---

## 10. Swift Migration Notes

| Concern | Scala approach | Swift approach |
|---------|---------------|----------------|
| Keyboard input | `KeyListener` with hard-coded VK constants | `NSEvent` / `UIKit` with configurable key→action map |
| Mouse input | Polled flags on `InteractionManager` | Delegate protocol with `mouseDown`, `mouseUp`, `mouseMoved` callbacks |
| Serial comms | RXTX library, synchronous constructor init | `IOKit` or `ORSSerialPort` with async delegate; deferred init |
| Input routing | `InteractionManager` singleton ref chain | Dependency injection; `InputContext` passed to sketch |
| Camera control | Global `Camera.translateSpeed` | `CameraController` struct with configurable sensitivity |
| Modifier state | Boolean flags, not reset on focus loss | Track via `NSEvent.modifierFlags`; reset in `windowDidResignKey` |
| Event model | Mixed polling + callback | Unified delegate protocol for all input sources |
