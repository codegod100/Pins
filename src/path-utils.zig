const std = @import("std");

// Minimal GLib/GIO declarations - avoid @cImport issues with macros
extern fn g_file_get_path(file: ?*anyopaque) ?[*:0]u8;
extern fn g_get_home_dir() [*:0]const u8;
extern fn g_strdup(str: ?[*:0]const u8) ?[*:0]u8;
extern fn g_free(ptr: ?*anyopaque) void;
extern fn g_malloc(size: usize) ?*anyopaque;

/// Get a formatted path string for a GFile, with ~ substitution for home directory.
/// Returns null if file is invalid. Caller must free returned string with g_free().
pub export fn get_display_path(file: ?*anyopaque) ?[*:0]u8 {
    if (file == null) return null;
    
    // Get path using GLib function
    const path = g_file_get_path(file) orelse return null;
    defer g_free(path);
    
    const path_len = std.mem.len(path);
    
    // Get home directory for ~ substitution
    const home = g_get_home_dir();
    const home_len = std.mem.len(home);
    
    // Check if path starts with home directory
    if (path_len >= home_len and std.mem.eql(u8, path[0..home_len], std.mem.span(home))) {
        const remaining = path[home_len..path_len];
        // Allocate: "~" + remaining + null terminator
        const result = g_malloc(remaining.len + 2) orelse return null;
        const result_bytes: [*]u8 = @ptrCast(result);
        result_bytes[0] = '~';
        @memcpy(result_bytes[1 .. remaining.len + 1], remaining);
        result_bytes[remaining.len + 1] = 0;
        return @ptrCast(result);
    }
    
    return g_strdup(path);
}