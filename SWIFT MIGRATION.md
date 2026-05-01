SWIFT MIGRATION

Technical:
	- keen to keep this state of the software as is.  Would prrefer to build this integrated SWIF version in a separate directory within Loom_2026.  Let's call it Loom_Swift_Integration and begin by copying any necessary resources from current directories into this one.  I'm assuming, for instance, that most of Swift Loom Engine can be copied directly in but I'm also thinking of associated features such as html documentation, etc.


- Structure:
	- Main components:
		1. run control bar:
			- include current play, pause, stop controls and frame count fields, status update and features from current run tab (quality multiple, scale image, animating, draw background once, save still, save animation and open renders directory)
		2. tabs to switch between global, project, geometry, subdivision, sprite and rendering perspectives ('run' tab to be eliminated)
		3. tab perspectives include 3 elements:
			a. list view at left related to the selected tab:
				- global tab - N/A (no list view)
					- note: move current features from run tab, render destination, Loom path, Loom output and auto-save before run/reload to global tab
				- project tab: tree view of current project - preview of items in main view when clicked on, including geometry, renders, brushes, palettes, background images, renders, etc.
				- geometry tab: hierarchical and foldable list of available project geometry organised in terms of algorithmic (regular polygons and ovals), polygonSets, curveSets and pointSets.  Each of these 4 major types of geometry will have a + sign associated with it that enables the user to create new geometry of that type.  Choosing to create or edit geometry will change main view from default geometry preview to a modal Bezier instance, which can either be used there or expanded to become a separate window. 
					- listed geometry sets will show name, number of associated sprites and include dedicated delete and duplicate icons.  Rename will be handled simply by clicking on sprite names and changing the name (which will also change the name on file)
					- don't think we need the various geometry set fields above the current preview window any longer but will need to find a place to incorporate 'include open curves' for polygonSets (perhaps as checkbox column in list view for that type of geometry?)
					- keep quickset up fields, but include dropdown to select form available subdivision sets (not just create new ones).
				- subdivision tab: hierarchical and foldable list of available subdivision sets, including name, type, inset, PTW and PTP fields, as well as additional icons deletion, duplication and baking.  Name field is editable for renaming.
					- subdivision settings now available preview in main view
					- need to include a sprite dropdown to select relevant sprites for subdivision preview (one or more sprite sets or sprites can be selected from dropdown)
				- sprites tab
					- hierarchical and foldable list of available sprites - including name, enabled, anim and duplicate and delete icons.  Renaming occurs by editing name field.  This also needs to include scope to create sprite sets and to drag sprites within this list view to arrange hierarchy.  This relates to features that have not properly been implemented yet, so that set level animation can occur as well as parent child hierarchies within sets.
					- clicking on sprite highlights sprite in main view and opens up its various parameters for editing in the parameter view: this will now also add in not only transformation/animation parameters but also the capacity to select from available subdivision and rendering sets.
					- selected sprites are highlighted in main view
				- rendering tab:
					- hierarchical and foldable list of available renderer sets and individual renderers.  Sprite dropdown to selection one or more sprite set or individual sprite to preview rednering in main window.
			b. parameter view that could either be placed beneath list view or possibly run across the bottom of the screen (will have to test what works best).  The parameters relate to the currently selected item in the list view:
				- global tab: shows global parameters (includeing some parameters currently in run tab)
				- subdivision tab: includes its own subtabs - general, Inset transform, PTW and PTP
				- sprites tab: includes general and animation tabs (note preview now occurs in main view)
			c. a main view of scene that varies according to the selected tab:
				- global tab - displays global parameters (not any aspect of the scene)
				- project view - preview of project items
				- geometry tab - defaults to wireframe view of geometry employed in the scene.  When user is creating or editing geometry switches to Bezier view.
				- subdivision tab - shows live preview of subdivison of selected sprite (from dropdown)
				- sprites tab - a larger view of the current animation preview window.
				- rendering tab - render preview of selected sprite from dropdown

Look and Feel
	- B & W, shades of grey
	- simple and understated


GUI
	- ensure all editable fields can accept appropriate values (sufficient decimal places, etc.)

