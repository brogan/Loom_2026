/**
 * 
 */
package org.brogan.scaffold;

import javax.swing.JFrame;
import org.brogan.ui.CubicCurveFrame;

/**
 * add one sentence class summary here
 * add class description here
 *
 * @author brogan
 * @version 1.0, Jul 19, 2006
 */
public class Main {
	
	public static void main(String[] args) {
		String saveDir = null;
		String loadFile = null;
		String name = null;
		boolean pointSelect = false;

		for (int i = 0; i < args.length; i++) {
			if ("--save-dir".equals(args[i]) && i + 1 < args.length) {
				saveDir = args[++i];
			} else if ("--load".equals(args[i]) && i + 1 < args.length) {
				loadFile = args[++i];
			} else if ("--name".equals(args[i]) && i + 1 < args.length) {
				name = args[++i];
			} else if ("--point-select".equals(args[i])) {
				pointSelect = true;
			}
		}

		if (saveDir != null || loadFile != null || name != null || pointSelect) {
			new CubicCurveFrame(saveDir, loadFile, name, pointSelect);
		} else {
			new CubicCurveFrame();
		}
	}

}
