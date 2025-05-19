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
- [ ] The current header / row shrinking doesn't size the cells correctly. Instead we need to remember which column was the tallest and if that
        column shrinks then redraw that column with a height of 0.

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


