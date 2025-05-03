### Todos

### Issues
- [ ] Columns flash when sorting. Only the separator is shown. The label is blank for some reason.
- [X] Headers never shrink when height shrinks
- [ ] If headers are bigger than cols, then doesn't show grid data until next refresh.
- [X] Sometimes there is an extra 1 row gap at the end of the grid in virtual scrolling mode.
- [X] The above is because of "window size". It is leaving an 'x' row gap at the bootom of the grid. Is window_size even worth it? YES!
- [ ] Is there a better name than window size for the scroller? It's not really a window size. It's a number of extra rows to draw above and below
- [X] checkbox header doesn't resize properly. separator needs gravity of 1. doesnt look right in undortable headers.
- [ ] scrolling header and body simultaneously is not a smooth as I'd like.
- [X] Need to add blank space for the "scrollbar width" in the header. Probably just always have it?
- [X] Issue with the scrolling override warnings for scrollinfo vs not.
- [ ] Checkbox doesn't expand to the full height of the header.
- [ ] Remove the need to pass the same (or sometimes different) styling to the header vs the body.
- [ ] Make column headers respect column width "ownership" so that .expand can be used on the body columns. 
- [ ] Virtual scrolling with large row heights doesn't work well because of the way it snaps to the next visible row.
- [ ] Grid header widget assumes vertical scroll bar width and that it will be displayed.

### Future
* Some better visual indication that columns are sortable.
* Make the GridWidget do the layout calculations, rather than relying on hbox / vbox layouts. 
    - Then each column have a style of fixed, expanding, size_to_content etc.
    - The grid Widget can then take into account the available space and size each column accordingy.
    - Potentially it would allows layout out data by row rather than just by col.
    - Would likely fix the issue of the header and body not being 100% in sync while scrolling.
* Resize columns via dragging
* Filtering headers


