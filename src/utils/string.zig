pub const SearchQuery = struct {
    fuzzy_search: bool,
    ignore_case: bool,
    query: []const u8,
};

// Left-pads a given string with specific characters.
//
// @param str: The input string to be padded
// @param len: The desired length of the output string
// @param padding_char: The character to use for padding
// @param buffer: A buffer to store the padded string
pub fn leftPadding(str: []const u8, len: usize, padding_char: u8, buffer: []u8) []u8 {
    // Calculates the diff b/w desired length and input string length
    const diff = len -| str.len;

    if (diff == 0) {
        @memcpy(buffer[0..str.len], str);
        return buffer[0..str.len];
    }

    @memset(buffer[0..diff], padding_char);
    @memcpy(buffer[diff..(diff + str.len)], str);

    return buffer[0..(diff + str.len)];
}

// Right-pads a given string with specific characters.
//
// @param str: The input string to be padded
// @param len: The desired length of the output string
// @param padding_char: The character to use for padding
// @param buffer: A buffer to store the padded string
pub fn rightPadding(str: []const u8, len: usize, padding_char: u8, buffer: []u8) []u8 {
    const diff = len -| str.len;

    if (diff == 0) {
        @memcpy(buffer[0..str.len], str);
        return buffer[0..str.len];
    }

    @memcpy(buffer[0..str.len], str);
    @memset(buffer[str.len..(diff + str.len)], padding_char);

    return buffer[0..(diff + str.len)];
}
