### Todos
- [ ] Make rows always the same height (potentially there should be a way to override this if user really wants?)
- [ ] As above for headers.
- [ ] Make sure rows and headers can grow and shrink.
- [ ] Make it so different options can be provided for the cell vs the label? Or will these never overlap? 
        - Using strip on hte options passed ot the label, causes height issues.
- [ ] Take the header clip from a measured height, rather than a constant 80.

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


