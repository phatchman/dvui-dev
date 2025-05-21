### Todos
- [ ] Look into making the grid take a content width as an init_option. This would size the width of the 
      scroll area, so that a .expand layout can fill the whole space.
- [ ] Get rid of the padding for the sortable header. It isn't const the size of the symbol is dependent on the font size?
- [X] Remove special casing of 0 for column width. It should either be no width provided, a positive width or get the default width if it is <= 0>.
- [X] Draws over horiztonal scroll bar. Need to adjust the clipping rect to take this into account.
- [ ] Handle padding when header column width is smaller than the heading button width. Currently doesn't show the separator.
- [ ] Several issues around whether scrollbars are showing and if padding needs to be applied, including columnLayoutProportional

### Issues
- [ ] When text is too wide for a column, the oversized text is displayed for 1 frame.
- [ ] Is there a better name than window size for the scroller? It's not really a window size. It's a number of extra rows to render above and below the visible rows.
- [X] Checkbox doesn't expand to the full height of the header.
- [ ] Grid header widget assumes vertical scroll bar width is 10 and that it will always be displayed. 
- [ ] Example needs to be added to Example.zig, rather than a stand-alone.
- [ ] Issue with grid headers moving while virtual scrolling. Header is set to scroll_info.vieport.y, but this is not always at the top of the viewport (due to floating point precision?)


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


