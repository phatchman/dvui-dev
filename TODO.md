### Todos
- [ ] Get rid of the padding for the sortable header. It isn't const the size of the symbol is dependent on the font size?
- [ ] Handle padding when header column width is smaller than the heading button width. Currently doesn't show the separator.
- [ ] Draws over vertical scroll bar when horizontal scrolling. Need to change the clip or reserve space for the scrollbar.
- [ ] Need some defalt padding, so the first column isn;t hard against the edge of the grid.
- [ ] Fix checkbox padding or size? It's not shown the speparator.

### Issues
- [ ] Is there a better name than window size for the scroller? It's not really a window size. It's a number of extra rows to render above and below the visible rows.
        - Windows size > 1 doesn't seem to make any difference really.
- [ ] Grid header widget assumes vertical scroll bar width is 10 and that it will always be displayed. 
- [ ] Example needs to be added to Example.zig, rather than a stand-alone.
- [ ] Issue with grid headers moving while virtual scrolling. Header is set to scroll_info.vieport.y, but this is not always at the top of the viewport (due to floating point precision?)
- [ ] Gravity is applied correctly when virtual scrolling? i..e things will only center when scrolling stops.
        - It doesn't happen with non-virtual scrolling, so something is not expanding correctly?
        - Actually, I'm not sure that is the case, They could just be being drawn in the wrong places and then corrected when the scrolling stops.
        - Need to investigate further.


### Future
* Some better visual indication that columns are sortable.
* Make the GridWidget do the layout calculations, rather than relying on hbox / vbox layouts. 
    - Then each column have a style of fixed, expanding, size_to_content etc.
    - The grid Widget can then take into account the available space and size each column accordingy.
    - Potentially it would allows layout out data by row rather than just by col.
    - Would likely fix the issue of the header and body not being 100% in sync while scrolling.
* Resize columns via dragging
* Filtering headers

## How do we treat options???
        // reset to defaults of internal widgets
        .id_extra = null, - Cell
        .tag = null, - Cell
        .name = null, - Cell
        .rect = null, - Ignored
        .min_size_content = null, - Ignored
        .max_size_content = null, - Cell
        .expand = null, - Label (Cell is always expanded.)
        .gravity_x = null,     - Label
        .gravity_y = null,     - Label

        // ignore defaults of internal widgets
        .tab_index = null, - Label
        .margin = Rect{}, - Label
        .border = Rect{},  - Cell
        .padding = Rect{}, - Cell
        .corner_radius = Rect{}, - Label
        .background = false, - Label (Cell always draw background?)

        // keep the rest
        .color_accent = self.color_accent,      - Label
        .color_text = self.color_text,  - Label
        .color_text_press = self.color_text_press,      - Label
        .color_fill = self.color_fill,  - Label / Cell
        .color_fill_hover = self.color_fill_hover, Label / Cell
        .color_fill_press = self.color_fill_press, Label
        .color_border = self.color_border, Label / Cell

        .font = self.font, Lable
        .font_style = self.font_style,

        .rotation = self.rotation,
        .debug = self.debug,


