package org.brogan.util;

import java.awt.Dimension;

import javax.swing.*;

public class Swing {
	/**
	 * Sets the size of a Swing component
	 * @param comp
	 * @param w
	 * @param h
	 */
	public static void setSize(JComponent comp, int w, int h) {
		Dimension dim = new Dimension(w,h);
		comp.setMinimumSize(dim);
		comp.setMaximumSize(dim);
		comp.setPreferredSize(dim);
	}
	/**
	 * Get int value of a JTextField
	 * @param field
	 * @return
	 */
	public static int getFieldIntValue (JTextField field) {
		return Integer.parseInt(field.getText());
	}
	/**
	 * Get float value of a JTextField
	 * @param field
	 * @return
	 */
	public static float getFieldFloatValue (JTextField field) {
		return Float.parseFloat(field.getText());
	}
	/**
	 * Get int value of a JTextField
	 * @param field
	 * @return
	 */
	public static double getFieldDoubleValue (JTextField field) {
		return Double.parseDouble(field.getText());
	}
	/**
	 * Get String value of a JTextField
	 * @param field
	 * @return
	 */
	public static String getFieldStringValue (JTextField field) {
		return field.getText();
	}
	/**
	 * Returns int value of selected item in JComboBox
	 * @param combo
	 * @return
	 */
	public static int getComboIntValue (JComboBox combo) {
		return Integer.parseInt((String)combo.getSelectedItem());
	}
	/**
	 * Returns float value of selected item in JComboBox
	 * @param combo
	 * @return
	 */
	public static float getComboFloatValue (JComboBox combo) {
		return Float.parseFloat((String)combo.getSelectedItem());
	}
	/**
	 * Returns String value of selected item in JComboBox
	 * @param combo
	 * @return
	 */
	public static String getComboStringValue (JComboBox combo) {
		return (String)combo.getSelectedItem();
	}
	/**
	 * Returns boolean value of JCheckBox
	 * @param box
	 * @return
	 */
	public static boolean getCheckBoxValue(JCheckBox box) {
		return box.isSelected();
	}
	/**
	 * checks to see if a name already exists in a JComboBox
	 * @param combo
	 * @param name
	 * @return
	 */
	public static boolean isNameInCombo(JComboBox combo, String name) {
		for (int p = 0; p < combo.getItemCount(); p++) {
			if (name.equals(combo.getItemAt(p).toString())) {
				return true;
			}
		}
		return false;
	}

}
