Todos
- [ ] Equal space, ratio, expanding column widths.
- [X] Header scrolling.
- [X] MAke horizontal scrolling work without passing a scroll info. I though this used to work?


Issues
- [ ] Columns flash when sorting. Like the label width isn't set for 1 frame or something?
- [ ] Headers never shrink when height shrinks
- [ ] If headers are bigger than cols, then doesn't show grid data until next refresh.
- [X] Sometimes there is an extra 1 row gap at the end of the grid in virtual scrolling mode.
- [X] The above is because of "window size". It is leaving an 'x' row gap at the bootom of the grid. Is window_size even worth it? YES!
- [ ] Is there a better name than window size for the scroller? It's not even a window size. It's a number of extra rows to draw above and below
- [X] checkbox header doesn't resize properly. separator needs gravity of 1. doesnt look right in undortable headers.
- [ ] scrolling header and body simultaneously is not a smooth as I'd like.
- [X] Need to add blank space for the "scrollbar width" in the header. Probably just always have it?

Notes
 - For fixed width columns need to pass the same min/max size to the header and the column.
