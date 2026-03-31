/*
 * PressureJNI.m — reads the current stylus pressure via NSEvent.pressure.
 *
 * Returned value is 0.0 for a regular mouse button press, and a positive
 * float (typically 0.0–1.0) for a pressure-sensitive stylus event.
 * We return 1.0 for regular mouse events so that no-stylus drawing looks normal.
 *
 * Build:  cd bezier/native && bash build_pressure_jni.sh
 */

#include <jni.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

JNIEXPORT jfloat JNICALL
Java_org_brogan_bezier_StylusPressureSource_getPressureNative(JNIEnv *env, jobject obj)
{
    @autoreleasepool {
        NSEvent *event = [NSApp currentEvent];
        if (event == nil) return 1.0f;
        float p = [event pressure];
        // Mouse click returns 0.0; treat that as full pressure for compatibility.
        return (p > 0.0f) ? (jfloat)p : 1.0f;
    }
}
