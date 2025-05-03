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
- [ ] scrolling has started to becomine a bit "jumpy". Not sure what has changed here.
- [ ] Issue with the scrolling override warnings for scrollinfo vs not.
- [ ] Checkbox doesn;t expand to the full height of the header.
- [ ] Remove the need to pass the same (or sometimes different) styling to the header vs the body.
- [ ] Make column headers respect "ownership" so that .expand can be used on the body columns. 
- [ ] Virtual scrolling with large row heights doesn't work well because of the way it snaps to the next visible row.

Ideas
* Some better visual indication that columns are sortable.

Notes
