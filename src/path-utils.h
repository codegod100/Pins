#pragma once

#include <gio/gio.h>

/**
 * Get a formatted path string for a GFile, with ~ substitution for home directory.
 * Returns NULL if file is invalid. Caller must free returned string with g_free().
 */
char *get_display_path(GFile *file);