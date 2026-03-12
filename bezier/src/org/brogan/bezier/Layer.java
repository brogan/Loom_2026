package org.brogan.bezier;

public class Layer {

    private static int nextId = 1;

    private final int id;
    private String name;
    private boolean visible;

    public Layer(String name) {
        this.id      = nextId++;
        this.name    = name;
        this.visible = true;
    }

    public int     getId()                  { return id; }
    public String  getName()                { return name; }
    public void    setName(String name)     { this.name = name; }
    public boolean isVisible()              { return visible; }
    public void    setVisible(boolean v)    { this.visible = v; }
}
