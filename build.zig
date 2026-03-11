const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Find pkg-config
    const pkg_config = b.findProgram(&[_][]const u8{"pkg-config"}, &[_][]const u8{}) catch {
        std.debug.print("Error: pkg-config not found\n", .{});
        return error.PkgConfigNotFound;
    };

    // Get GTK4 flags
    const gtk4_cflags = b.run(&.{ pkg_config, "--cflags", "gtk4" });
    const gtk4_libs = b.run(&.{ pkg_config, "--libs", "gtk4" });

    // Get libadwaita flags
    const adwaita_cflags = b.run(&.{ pkg_config, "--cflags", "libadwaita-1" });
    const adwaita_libs = b.run(&.{ pkg_config, "--libs", "libadwaita-1" });

    // Generate config.h
    const config_h = b.addWriteFiles();
    const config_path = config_h.add("config.h", 
        \\#pragma once
        \\#define GETTEXT_PACKAGE "pinapp"
        \\#define LOCALEDIR "/usr/local/share/locale"
        \\#define PACKAGE_VERSION "0.1.0"
        \\
    );

    // Generate gresources to a fixed location
    const gen_resources = b.addSystemCommand(&.{
        "glib-compile-resources",
        "src/pins.gresource.xml",
        "--target=zig-out/pins-resources.c",
        "--sourcedir=src",
        "--sourcedir=data/icons/scalable/actions",
        "--generate-source",
    });
    gen_resources.setCwd(b.path(""));
    gen_resources.has_side_effects = true;

    // Reference the generated file directly (no addOutputFileArg to avoid extra argument)
    const gresource_file = b.path("zig-out/pins-resources.c");

    // Parse cflags
    var cflags = try std.ArrayList([]const u8).initCapacity(b.allocator, 32);
    defer cflags.deinit(b.allocator);

    var gtk4_cflags_iter = std.mem.splitScalar(u8, std.mem.trim(u8, gtk4_cflags, " \n\t"), ' ');
    while (gtk4_cflags_iter.next()) |flag| {
        if (flag.len > 0) try cflags.append(b.allocator, b.dupe(flag));
    }

    var adwaita_cflags_iter = std.mem.splitScalar(u8, std.mem.trim(u8, adwaita_cflags, " \n\t"), ' ');
    while (adwaita_cflags_iter.next()) |flag| {
        if (flag.len > 0) try cflags.append(b.allocator, b.dupe(flag));
    }

    // Create root module
    const root_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    // Executable
    const exe = b.addExecutable(.{
        .name = "pinapp",
        .root_module = root_mod,
    });

    exe.addIncludePath(b.path("src"));
    exe.addIncludePath(config_path.dirname()); // for generated config.h
    exe.addIncludePath(b.path("zig-out")); // for generated pins-resources.h
    
    // Ensure gresources are generated before compiling
    exe.step.dependOn(&gen_resources.step);

    // C sources
    const c_sources = [_][]const u8{
        "main.c",
        "pins-add-key-dialog.c",
        "pins-app-filter.c",
        "pins-app-grid.c",
        "pins-app-icon.c",
        "pins-app-iterator.c",
        "pins-app-tile.c",
        "pins-app-view.c",
        "pins-application.c",
        "pins-desktop-file.c",
        "pins-directories.c",
        "pins-file-view.c",
        "pins-key-row.c",
        "pins-locale-utils.c",
        "pins-pick-icon-popover.c",
        "pins-window.c",
    };

    for (c_sources) |src| {
        exe.addCSourceFile(.{
            .file = b.path(b.pathJoin(&.{ "src", src })),
            .flags = cflags.items,
        });
    }

    // Generated gresource source
    exe.addCSourceFile(.{
        .file = gresource_file,
        .flags = cflags.items,
    });

    exe.linkLibC();

    // Parse and add library link flags
    const all_libs = try std.mem.concat(b.allocator, u8, &.{ std.mem.trim(u8, gtk4_libs, " \n\t"), " ", std.mem.trim(u8, adwaita_libs, " \n\t") });

    var lib_iter = std.mem.splitScalar(u8, all_libs, ' ');
    while (lib_iter.next()) |lib| {
        const trimmed = std.mem.trim(u8, lib, " \n\t");
        if (trimmed.len == 0) continue;

        if (std.mem.startsWith(u8, trimmed, "-l")) {
            exe.linkSystemLibrary(trimmed[2..]);
        } else if (std.mem.startsWith(u8, trimmed, "-L")) {
            exe.addLibraryPath(.{ .cwd_relative = trimmed[2..] });
        }
    }

    // Install executable
    b.installArtifact(exe);

    // Install gsettings schema
    b.installFile("data/io.github.fabrialberio.pinapp.gschema.xml", "share/glib-2.0/schemas/io.github.fabrialberio.pinapp.gschema.xml");

    // Compile schemas step
    const compile_schemas = b.addSystemCommand(&.{
        "glib-compile-schemas",
        b.getInstallPath(.prefix, "share/glib-2.0/schemas"),
    });
    compile_schemas.step.dependOn(b.getInstallStep());

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.setEnvironmentVariable("GSETTINGS_SCHEMA_DIR", b.getInstallPath(.prefix, "share/glib-2.0/schemas"));

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Dev run (uses local data directory for schemas)
    const dev_schemas = b.addSystemCommand(&.{
        "glib-compile-schemas",
        "data",
    });
    dev_schemas.setCwd(b.path(""));
    dev_schemas.has_side_effects = true;

    const dev_run_cmd = b.addRunArtifact(exe);
    dev_run_cmd.setEnvironmentVariable("GSETTINGS_SCHEMA_DIR", "data");
    dev_run_cmd.step.dependOn(&dev_schemas.step);

    const dev_step = b.step("dev", "Run with development environment");
    dev_step.dependOn(&dev_run_cmd.step);
}
