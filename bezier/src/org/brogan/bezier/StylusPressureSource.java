package org.brogan.bezier;

/**
 * JNI-backed PressureSource that reads NSEvent.pressure on macOS.
 * If the native library cannot be loaded, createBest() returns a fallback
 * that always reports 1.0f (equivalent to a regular mouse click).
 *
 * Build the native library with:
 *   cd bezier/native && bash build_pressure_jni.sh
 */
public class StylusPressureSource implements PressureSource {

    private static final boolean nativeLoaded;

    static {
        boolean loaded = false;
        // 1. Try java.library.path (e.g. -Djava.library.path=libs)
        try {
            System.loadLibrary("PressureJNI");
            loaded = true;
        } catch (UnsatisfiedLinkError e1) {
            // 2. Try paths relative to the working directory / known project location
            String[] candidates = {
                System.getProperty("user.dir") + "/libs/libPressureJNI.dylib",
                System.getProperty("user.home") + "/Loom_2026/bezier/libs/libPressureJNI.dylib"
            };
            for (String path : candidates) {
                try {
                    System.load(path);
                    loaded = true;
                    break;
                } catch (UnsatisfiedLinkError e2) {
                    // try next
                }
            }
        }
        nativeLoaded = loaded;
        if (nativeLoaded) {
            System.out.println("StylusPressureSource: native library loaded — stylus pressure enabled.");
        } else {
            System.out.println("StylusPressureSource: native library not found — using mouse fallback (pressure = 1.0).");
        }
    }

    /** True if the native library was successfully loaded. */
    public static boolean isNativeLoaded() { return nativeLoaded; }

    /**
     * Returns a PressureSource appropriate for this runtime:
     * a StylusPressureSource if the JNI library is available,
     * otherwise a lambda that always returns 1.0f.
     */
    public static PressureSource createBest() {
        if (nativeLoaded) return new StylusPressureSource();
        return () -> 1.0f;
    }

    private StylusPressureSource() {}

    @Override
    public float getPressure() {
        float p = getPressureNative();
        return Math.max(0.05f, Math.min(1.0f, p));
    }

    private native float getPressureNative();
}
