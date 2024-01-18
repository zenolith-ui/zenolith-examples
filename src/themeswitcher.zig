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
    label: *zl.widget.Widget,
    latte_btn: *zl.widget.Widget,
    frappe_btn: *zl.widget.Widget,
    macchiato_btn: *zl.widget.Widget,
    mocha_btn: *zl.widget.Widget,

    pub fn init(alloc: std.mem.Allocator) !*zl.widget.Widget {
        const vbox = try zl.widget.Box.init(alloc, .vertical);
        errdefer vbox.deinit();

        try vbox.addChild(null, try zl.widget.Label.init(alloc, "An example demonstrating theming in Zenolith."));
        try vbox.addChild(null, try zl.widget.Label.init(alloc, "Use the buttons below to change the theme!"));
        try vbox.addChild(null, try zl.widget.Spacer.init(alloc, .{ .fixed = .{ .width = 0, .height = 20 } }));
        const label = try zl.widget.Label.init(alloc, "Current Theme: Mocha");
        try vbox.addChild(null, label);
        try vbox.addChild(null, try zl.widget.Spacer.init(alloc, .{ .fixed = .{ .width = 0, .height = 20 } }));

        const hbox = try zl.widget.Box.init(alloc, .horizontal);

        const latte_btn = try zl.widget.Button.init(alloc, "Latte");
        const frappe_btn = try zl.widget.Button.init(alloc, "Frappe");
        const macchiato_btn = try zl.widget.Button.init(alloc, "Macchiato");
        const mocha_btn = try zl.widget.Button.init(alloc, "Mocha");

        try hbox.addChild(null, latte_btn);
        try hbox.addChild(null, try zl.widget.Spacer.init(alloc, .{ .flex = 1 }));
        try hbox.addChild(null, frappe_btn);
        try hbox.addChild(null, try zl.widget.Spacer.init(alloc, .{ .flex = 1 }));
        try hbox.addChild(null, macchiato_btn);
        try hbox.addChild(null, try zl.widget.Spacer.init(alloc, .{ .flex = 1 }));
        try hbox.addChild(null, mocha_btn);

        try vbox.addChild(null, hbox);

        const self = Root{
            .box = vbox,

            .label = label,
            .latte_btn = latte_btn,
            .frappe_btn = frappe_btn,
            .macchiato_btn = macchiato_btn,
            .mocha_btn = mocha_btn,
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

            else => try tv.dispatch(selfw),
        }
    }

    /// Called upon this widget receiving a backevent. Backevents are events which travel the
    /// widget tree upwards. Buttons emit the ButtonActivated backevent upon being clicked.
    pub fn backevent(self: *Root, selfw: *zl.widget.Widget, be: zl.backevent.Backevent) !void {
        if (be.downcast(zl.backevent.ButtonActivated)) |ba| {
            const theme = if (ba.btn_widget == self.latte_btn)
                zl.Theme.catppuccin_latte
            else if (ba.btn_widget == self.frappe_btn)
                zl.Theme.catppuccin_frappe
            else if (ba.btn_widget == self.macchiato_btn)
                zl.Theme.catppuccin_macchiato
            else if (ba.btn_widget == self.mocha_btn)
                zl.Theme.catppuccin_mocha
            else
                return;

            try theme.apply(selfw.data.allocator, &selfw.data.attreebutes.?);

            const text = if (ba.btn_widget == self.latte_btn)
                "Latte"
            else if (ba.btn_widget == self.frappe_btn)
                "Frappe"
            else if (ba.btn_widget == self.macchiato_btn)
                "Macchiato"
            else if (ba.btn_widget == self.mocha_btn)
                "Mocha"
            else
                return;
            // update label text
            var buf: [64]u8 = undefined;
            try self.label.downcast(zl.widget.Label).?.span.?.updateGlyphs(.{
                .text = try std.fmt.bufPrint(&buf, "Active Theme: {s}", .{text}),
            });
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
};

pub fn main() !void {
    const alloc = std.heap.c_allocator;

    // Initialize the SDL2 platform.
    var platform = try zsdl2.Sdl2Platform.init(.{ .alloc = alloc });
    defer platform.deinit();

    // Use the platform to create a font. Font discovery will be supported in a future version.
    var font = zl.text.Font.create(try platform.createFont(.{
        .source = .{ .data = @import("assets").liberation_sans_regular },
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
