package org.brogan.bezier;

import java.util.ArrayDeque;

/**
 * Fixed-depth undo stack for Bezier geometry snapshots.
 * Supports up to MAX_DEPTH levels of undo; the oldest entry is dropped when full.
 */
public class UndoManager {

    private static final int MAX_DEPTH = 20;
    private final ArrayDeque<GeometrySnapshot> stack = new ArrayDeque<>();

    /**
     * Push a snapshot onto the stack.
     * Drops the oldest entry if the stack would exceed MAX_DEPTH.
     */
    public void push(GeometrySnapshot snap) {
        if (stack.size() >= MAX_DEPTH) stack.removeFirst();
        stack.addLast(snap);
    }

    /**
     * Pop and return the most recent snapshot, or null if the stack is empty.
     */
    public GeometrySnapshot pop() {
        return stack.isEmpty() ? null : stack.removeLast();
    }

    public boolean isEmpty() { return stack.isEmpty(); }
    public int     size()    { return stack.size(); }
}
