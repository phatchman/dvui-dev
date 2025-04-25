Todos
- [ ] Equal space, ratio, expanding column widths.


Issues
- [ ] Columns flash when sorting. Like the label width isn't set for 1 frame or something?
- [ ] Headers never shrink
- [ ] If headers are bigger than cols, then doesn't show grid data until next refresh.
- [X] Sometimes there is an extra 1 row gap at the end of the grid in virtual scrolling mode.
- [X] The above is because of "window size". It is leaving an 'x' row gap at the bootom of the grid. Is window_size even worth it? YES!
- [ ] Is there a better name than window size for the scroller? It's not even a window size. It's a number of extra rows to draw above and below

Notes
 - For fixed width columns need to pass the same min/max size to the header and the column.