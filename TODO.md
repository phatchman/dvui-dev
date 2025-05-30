# Original Goals Completed
- [X] Display of a fixed header row with a scrollable data area beneath it.
- [X] Provide various column layouts (e.g. fit to window, proportional layout, fixed_width, user calculated)
- [X] Ability to sort data by clicking on header rows
- [X] Display sort direction
- [X] Ability to select rows via checkbox
- [X] Horizontal / Vertical scrolling
- [X] Virtual scrolling (only render visible elements)
- [X] "Databound" columns - gridColumnFromSlice
- [X] User customizable cell and column styling and layouts
- [X] Ability to highlight hovered rows (userland)

### Todos
- [X] Get rid of the padding for the sortable header. It isn't const the size of the symbol is dependent on the font size?
- [X] Handle padding when header column width is smaller than the heading button width. Currently doesn't show the separator.
- [X] Need some defalt padding, so the first column isn;t hard against the edge of the grid.
- [X] Fix checkbox separator when placed in an oversized column (or too small column)
- [X] Change mouse pointer and behavior when hovering over grid. i.e. stop the "move window" functionality that happens when clicking on a demo grid today.
        - This needs to be a change in the floating window behavior

### Issues
- [X] Grid header widget assumes vertical scroll bar width is 10 and that it will always be displayed. 
- [ ] Headers "wobble" with large virtual row heights. Almost certainly fp precision issue
        - Header is set to y position of scroll_info.virtual_size.y, but this doesn't always correspond to the top-left of the window.
        - Doubt this is solvable unless draw headers independently of the scroll canvas. i.e. relative to the outer grid's box?
- [ ] For 1 million rows our scroll height calc is out by 0.5 lines. Maybe out some small padding to add to compensate for large numbers.
- [X] Variable row heights demo seems to have an extra pixlel between rows?
        - Bug with 

### Remaining Goals
* Some better visual indication that columns are sortable.
* Resize columns via dragging 
* Filtering headers - May not be worth providing anything generic here. Likely just an example of string filtering.
* Drag / Drop? - Guessing this can be implemented in user-land. Likely just needs an example.
* Keyboard naviagtion / selection - Likely userland and example only as well.
