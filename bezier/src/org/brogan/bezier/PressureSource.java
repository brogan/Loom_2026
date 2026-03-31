package org.brogan.bezier;

/**
 * Source of stylus/mouse pressure, normalised to [0.0, 1.0].
 * Default (mouse, no stylus) returns 1.0f.
 */
@FunctionalInterface
public interface PressureSource {
    /** Returns current pressure in the range [0.0, 1.0]. */
    float getPressure();
}
