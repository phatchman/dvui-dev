### Todos
- [ ] Make rows always the same height (potentially there should be a way to override this if user really wants?)
- [ ] As above for headers.
- [ ] Make sure rows and headers can grow and shrink.
- [ ] Make it so different options can be provided for the cell vs the label? Or will these never overlap? 
        - Using strip on hte options passed ot the label, causes height issues.
- [ ] Take the header clip from a measured height, rather than a constant 80.
- [ ] Look into making the grid take a content width as an init_option. This would size the width of the 
      scroll area, so that a .expand layout can fill the whole space.
- [ ] Provide some osrt pf init options to put the header and body row heights under the control of the user.
        - They would be responsible for providing a min/max size content on each cell to make the rows line up
        however they neeed.

- So we need a different height for headers vs body. So max_content_size.h can be specified for both headers and bodies
- When layout ot the rows, use the row_height if supplied, otherwise use the calculated row height
- Grid should store the max row_height for the previous frame, separately for both header and body
- This should be used when laying out the position of the next row. (will prob need a refresh if this size changes)

### Issues
- [ ] When text is too wide for a column, the oversized text is displayed for 1 frame.
- [ ] Is there a better name than window size for the scroller? It's not really a window size. It's a number of extra rows to render above and below the visible rows.
- [ ] Checkbox doesn't expand to the full height of the header.
- [ ] Grid header widget assumes vertical scroll bar width is 10 and that it will always be displayed. 
- [ ] Example needs to be added to Example.zig, rather than a stand-alone.

### Future
* Some better visual indication that columns are sortable.
* Make the GridWidget do the layout calculations, rather than relying on hbox / vbox layouts. 
    - Then each column have a style of fixed, expanding, size_to_content etc.
    - The grid Widget can then take into account the available space and size each column accordingy.
    - Potentially it would allows layout out data by row rather than just by col.
    - Would likely fix the issue of the header and body not being 100% in sync while scrolling.
* Resize columns via dragging
* Filtering headers


