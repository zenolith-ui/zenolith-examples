const std = @import("std");
const zl = @import("zenolith");
const zsdl2 = @import("zenolith-sdl2");

pub const zenolith_options = struct {
    // Register zenolith-sdl2 platform and painter implementations.
    // This is required as Zenolith builds a statspatch type from these.
    // See: https://git.mzte.de/lordmzte/statspatch
    pub const platform_impls = [_]type{zsdl2.Sdl2Platform};
    pub const painter_impls = [_]type{zsdl2.Sdl2Painter};

    // Register widget implementations: builtin implementations and our Root widget.
    pub const widget_impls = zl.default_widget_impls ++ [_]type{Root};

    // Enable to draw debug information.
    //pub const debug_render = true;
};

/// Our root widget type. Most functions in here will be invoked by Zenolith.
const Root = struct {
    // We use this box as our only child widget. It will contain our buttons and a label.
    box: *zl.widget.Widget,

    // These aren't immediate children, we just save them have to be able to easily reference them.
    // Zenolith will take care of freeing these.
    sub_btn: *zl.widget.Widget,
    label: *zl.widget.Widget,
    add_btn: *zl.widget.Widget,

    counter: i32,

    pub fn init(alloc: std.mem.Allocator) !*zl.widget.Widget {
        const vbox = try zl.widget.Box.init(alloc, .vertical);
        errdefer vbox.deinit();

        try vbox.addChild(null, try zl.widget.Label.init(alloc, "A simple counter example."));
        try vbox.addChild(null, try zl.widget.Label.init(alloc, "Use the '+' and '-' buttons to change the counter!"));
        try vbox.addChild(null, try zl.widget.Spacer.init(alloc, .{ .fixed = .{ .width = 0, .height = 20 } }));

        const hbox = try zl.widget.Box.init(alloc, .horizontal);

        const sub_btn = try zl.widget.Button.init(alloc, "-");
        try hbox.addChild(null, sub_btn); // null => append to end

        // Add a spacer with a flex-expand of 1. This works somewhat like
        // (but not completely identical to) CSS.
        try hbox.addChild(null, try zl.widget.Spacer.init(alloc, .{ .flex = 1 }));

        const label = try zl.widget.Label.init(alloc, "0");
        try hbox.addChild(null, label);

        try hbox.addChild(null, try zl.widget.Spacer.init(alloc, .{ .flex = 1 }));

        const add_btn = try zl.widget.Button.init(alloc, "+");
        try hbox.addChild(null, add_btn);

        try vbox.addChild(null, hbox);
        try vbox.addChild(null, try zl.widget.Spacer.init(alloc, .{ .flex = 1 }));
        try vbox.addChild(null, try zl.widget.Label.init(alloc, "Hint: also try the plus and minus keys or tab + space!"));

        const self = Root{
            .box = vbox,

            .sub_btn = sub_btn,
            .label = label,
            .add_btn = add_btn,

            .counter = 0,
        };

        return try zl.widget.Widget.init(alloc, self);
    }

    /// This is called by Zenolith whenever a treevent is fired on our widget tree.
    /// We'll handle a few ones, and simply call the default dispatcher on others.
    pub fn treevent(self: *Root, selfw: *zl.widget.Widget, tv: anytype) !void {
        switch (@TypeOf(tv)) {
            // The LayoutSize treevent is fired when a layout path is being done on the Widget tree.
            // We'll simply let the Box do it's layout and use the exact same size.
            // We force box to use the maximum available size (= the window's size),
            // so it takes up all space.
            zl.treevent.LayoutSize => {
                var tvv = tv;
                tvv.constraints = zl.layout.Constraints.tight(tv.constraints.max);
                try self.box.treevent(tvv);
                selfw.data.size = self.box.data.size;
            },

            // This event is fired when a letter is typed.
            *zl.treevent.CharType => {
                // Dispatch the key event to children first...
                try tv.dispatch(selfw);

                // If no child handled it, and it's a press event..
                if (!tv.handled) {
                    // ... update the counter accordingly
                    switch (tv.codepoint) {
                        '+' => {
                            self.counter +%= 1;
                            try self.updateLabel();
                        },
                        '-' => {
                            self.counter -%= 1;
                            try self.updateLabel();
                        },
                        else => {},
                    }
                }
            },

            else => try tv.dispatch(selfw),
        }
    }

    /// Called upon this widget receiving a backevent. Backevents are events which travel the
    /// widget tree upwards. Buttons emit the ButtonActivated backevent upon being clicked.
    pub fn backevent(self: *Root, selfw: *zl.widget.Widget, be: zl.backevent.Backevent) !void {
        if (be.downcast(zl.backevent.ButtonActivated)) |ba| {
            if (ba.btn_widget == self.add_btn) {
                self.counter +%= 1;
            } else if (ba.btn_widget == self.sub_btn) {
                self.counter -%= 1;
            }
            try self.updateLabel();
        } else {
            // Dispatch other backevents.
            try be.dispatch(selfw);
        }
    }

    /// This function is required so Zenolith can operate on our child widgets.
    pub fn children(self: *Root, selfw: *zl.widget.Widget) []const *zl.widget.Widget {
        _ = selfw;
        return @as([*]const *zl.widget.Widget, @ptrCast(&self.box))[0..1];
    }

    fn updateLabel(self: *Root) !void {
        // update label text
        var buf: [64]u8 = undefined;
        try self.label.downcast(zl.widget.Label).?.span.?.updateGlyphs(.{
            .text = try std.fmt.bufPrint(&buf, "{}", .{self.counter}),
        });
    }
};

pub fn main() !void {
    const alloc = std.heap.c_allocator;

    // Initialize the SDL2 platform.
    var platform = try zsdl2.Sdl2Platform.init(.{ .alloc = alloc });
    defer platform.deinit();

    // Use the platform to create a font. Font discovery will be supported in a future version.
    var font = zl.text.Font.create(try platform.createFont(.{
        .source = .{ .path = "/usr/share/fonts/liberation/LiberationSans-Regular.ttf" },
    }), {});
    defer font.deinit();

    // Create statspatch-based platform type for use by platform-agnostic code.
    var zplatf = zl.platform.Platform.create(platform, .{});

    const root = try Root.init(alloc);
    defer root.deinit();

    // Create an AttreebuteMap for the root widget.
    // Attreebutes are tree-bound attributes, which are inherited to child widgets.
    // They're backed by a type-indexed map (think ECS).
    {
        var attrs = zl.attreebute.AttreebuteMap.init();
        errdefer attrs.deinit(alloc);

        // This is required by various widgets in order to render text.
        (try attrs.mod(alloc, zl.attreebute.CurrentFont)).* = .{ .font = &font };

        // This sets a variety of theming-related attributes to the builtin catppuccin mocha theme.
        try zl.Theme.catppuccin_mocha.apply(alloc, &attrs);

        root.data.attreebutes = attrs;
    }

    // This links the widget tree (ie. correctly sets parent pointers and updates the platform).
    // Some widgets also do initialization here.
    try root.link(null, &zplatf);

    // Run the main event loop until the application is closed;
    try platform.run(root);
}
