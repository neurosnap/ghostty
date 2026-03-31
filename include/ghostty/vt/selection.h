/**
 * @file selection.h
 *
 * Terminal text selection API.
 */

#ifndef GHOSTTY_VT_SELECTION_H
#define GHOSTTY_VT_SELECTION_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <ghostty/vt/types.h>
#include <ghostty/vt/allocator.h>
#include <ghostty/vt/point.h>

/* Forward declaration to avoid circular include with terminal.h.
 * The full typedef is in terminal.h. */
#ifndef GHOSTTY_VT_TERMINAL_H
typedef struct GhosttyTerminalImpl* GhosttyTerminal;
#endif

#ifdef __cplusplus
extern "C" {
#endif

/** @defgroup selection Selection
 *
 * Terminal text selection API.
 *
 * These functions manage text selections on the terminal's active screen.
 * A selection is defined by a start and end point (in any supported
 * coordinate system) and can be either a normal character-wise selection
 * or a rectangular (block) selection.
 *
 * ## Example: Creating a selection and extracting text
 *
 * @code{.c}
 * // Select columns 0-4 on row 0 (viewport coordinates)
 * GhosttyPoint start = { .tag = GHOSTTY_POINT_TAG_VIEWPORT,
 *                         .value.coordinate = { .x = 0, .y = 0 } };
 * GhosttyPoint end   = { .tag = GHOSTTY_POINT_TAG_VIEWPORT,
 *                         .value.coordinate = { .x = 4, .y = 0 } };
 * ghostty_terminal_select(term, start, end, false);
 *
 * // Extract the selected text
 * size_t len = 0;
 * ghostty_terminal_selection_to_string(term, NULL, 0, &len);
 * char *buf = malloc(len + 1);
 * ghostty_terminal_selection_to_string(term, (uint8_t *)buf, len, &len);
 * buf[len] = '\0';
 *
 * // Clean up
 * ghostty_terminal_select_clear(term);
 * free(buf);
 * @endcode
 *
 * @{
 */

/**
 * Set a selection on the terminal's active screen.
 *
 * Creates a selection from @p start to @p end in the given coordinate
 * system. If @p rectangle is true the selection is rectangular (block
 * mode); otherwise it is a normal character-wise selection.
 *
 * Any existing selection is replaced.
 *
 * @param terminal The terminal handle (NULL returns GHOSTTY_INVALID_VALUE)
 * @param start    The start point of the selection
 * @param end      The end point of the selection
 * @param rectangle  Whether this is a rectangular (block) selection
 * @return GHOSTTY_SUCCESS on success, GHOSTTY_INVALID_VALUE if the terminal
 *         is NULL or either point is out of bounds, GHOSTTY_OUT_OF_MEMORY
 *         on allocation failure
 *
 * @ingroup selection
 */
GHOSTTY_API GhosttyResult ghostty_terminal_select(GhosttyTerminal terminal,
                                                   GhosttyPoint start,
                                                   GhosttyPoint end,
                                                   bool rectangle);

/**
 * Clear the current selection on the terminal's active screen.
 *
 * If there is no selection, this is a no-op.
 *
 * @param terminal The terminal handle (may be NULL, in which case this is a no-op)
 *
 * @ingroup selection
 */
GHOSTTY_API void ghostty_terminal_select_clear(GhosttyTerminal terminal);

/**
 * Check whether the terminal's active screen has a selection.
 *
 * @param terminal The terminal handle (NULL returns GHOSTTY_INVALID_VALUE)
 * @param[out] out_has On success, set to true if a selection exists
 * @return GHOSTTY_SUCCESS on success
 *
 * @ingroup selection
 */
GHOSTTY_API GhosttyResult ghostty_terminal_has_selection(GhosttyTerminal terminal,
                                                          bool *out_has);

/**
 * Check whether the given point is contained within the current selection.
 *
 * @param terminal The terminal handle (NULL returns GHOSTTY_INVALID_VALUE)
 * @param point    The point to test
 * @param[out] out_contained On success, set to true if the point is selected
 * @return GHOSTTY_SUCCESS on success, GHOSTTY_NO_VALUE if there is no selection,
 *         GHOSTTY_INVALID_VALUE if the terminal is NULL or the point is out of bounds
 *
 * @ingroup selection
 */
GHOSTTY_API GhosttyResult ghostty_terminal_selection_contains(GhosttyTerminal terminal,
                                                               GhosttyPoint point,
                                                               bool *out_contained);

/**
 * Get the ordered top-left and bottom-right bounds of the current selection
 * in viewport coordinates.
 *
 * Either output pointer may be NULL if the caller does not need that value.
 *
 * @param terminal The terminal handle (NULL returns GHOSTTY_INVALID_VALUE)
 * @param[out] out_top_left On success, the top-left coordinate (may be NULL)
 * @param[out] out_bottom_right On success, the bottom-right coordinate (may be NULL)
 * @param[out] out_rectangle On success, whether the selection is rectangular (may be NULL)
 * @return GHOSTTY_SUCCESS on success, GHOSTTY_NO_VALUE if there is no selection,
 *         GHOSTTY_INVALID_VALUE if the terminal is NULL or bounds cannot be resolved
 *
 * @ingroup selection
 */
GHOSTTY_API GhosttyResult ghostty_terminal_selection_bounds(GhosttyTerminal terminal,
                                                             GhosttyPointCoordinate *out_top_left,
                                                             GhosttyPointCoordinate *out_bottom_right,
                                                             bool *out_rectangle);

/**
 * Extract the selected text as a UTF-8 string into a caller-provided buffer.
 *
 * If @p buf is NULL or @p buf_len is too small, returns GHOSTTY_OUT_OF_SPACE
 * and sets @p out_len to the required buffer size. On success, @p out_len is
 * set to the number of bytes written (not including any terminator).
 *
 * Soft-wrapped lines are unwrapped and trailing whitespace is trimmed.
 *
 * @param terminal The terminal handle (NULL returns GHOSTTY_INVALID_VALUE)
 * @param buf      Output buffer (may be NULL to query required size)
 * @param buf_len  Size of the output buffer in bytes
 * @param[out] out_len On success, the number of bytes written. On
 *             GHOSTTY_OUT_OF_SPACE, the required buffer size.
 * @return GHOSTTY_SUCCESS on success, GHOSTTY_NO_VALUE if there is no selection,
 *         GHOSTTY_OUT_OF_SPACE if the buffer is too small
 *
 * @ingroup selection
 */
GHOSTTY_API GhosttyResult ghostty_terminal_selection_to_string(GhosttyTerminal terminal,
                                                                uint8_t *buf,
                                                                size_t buf_len,
                                                                size_t *out_len);

/**
 * Extract the selected text as a UTF-8 string, allocating the buffer.
 *
 * The returned buffer is null-terminated. The caller must free it with
 * ghostty_free() using the same allocator (or NULL for the default).
 * The @p out_len value does not include the null terminator.
 *
 * Soft-wrapped lines are unwrapped and trailing whitespace is trimmed.
 *
 * @param terminal  The terminal handle (NULL returns GHOSTTY_INVALID_VALUE)
 * @param allocator Pointer to allocator, or NULL to use the default allocator
 * @param[out] out_ptr On success, pointer to the allocated buffer
 * @param[out] out_len On success, the length of the string in bytes
 *                     (not including null terminator)
 * @return GHOSTTY_SUCCESS on success, GHOSTTY_NO_VALUE if there is no selection,
 *         GHOSTTY_OUT_OF_MEMORY on allocation failure
 *
 * @ingroup selection
 */
GHOSTTY_API GhosttyResult ghostty_terminal_selection_to_string_alloc(GhosttyTerminal terminal,
                                                                      const GhosttyAllocator *allocator,
                                                                      uint8_t **out_ptr,
                                                                      size_t *out_len);

/** @} */

#ifdef __cplusplus
}
#endif

#endif /* GHOSTTY_VT_SELECTION_H */
