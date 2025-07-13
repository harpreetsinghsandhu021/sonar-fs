// IconManager Handles File type icon mapping for the File Explorer.
// It matches file extenstions and types to their corresponding icons.
const std = @import("std");
const path = std.fs.path;
const Entry = @import("../../fs/fsIterator.zig").Entry;
const icons = @import("./icons.zig").icons;

// Returns the appropriate icon for a given file entry
pub fn getIcon(entry: *Entry) ![]const u8 {
    const item = entry.item;

    var extension = path.extension(item.getAbsolutePath());
    if (extension.len == 0) {
        extension = item.getBasename();
    }

    // Try matching file extension to an icon
    if (findIconForExtension(extension)) |icon| {
        return icon;
    }

    const file_stat = try item.getStat();
    if (file_stat.isDir()) {
        if (item.hasChildren()) {
            return icons.folder_span;
        } else {
            return icons.folder;
        }
    }

    if (file_stat.isBlockFile() or file_stat.isCharSpecialFile()) {
        return icons.file_empty;
    }

    return icons.file;
}

// Groups File extensions by their associated technologies and returns corresponding icons
fn findIconForExtension(ext: []const u8) ?[]const u8 {
    // Programming Language Groups

    // Python family
    if (isPythonFile(ext)) return icons.python;

    // JS/TS family
    if (isJavascriptFile(ext)) return icons.javascript;
    if (isTypescriptFile(ext)) return icons.typescript;

    // Web Technologies
    if (isWebFile(ext)) return getWebIcon(ext);

    // Systems Programming
    if (isCFile(ext)) return icons.c;
    if (isCppFile(ext)) return icons.cpp;
    if (std.mem.eql(u8, ext, ".rs")) return icons.rust;
    if (std.mem.eql(u8, ext, ".zig")) return icons.zig;
    if (std.mem.eql(u8, ext, ".go")) return icons.go;
    if (std.mem.eql(u8, ext, ".asm")) return icons.assembly;

    // JVM Languages
    if (isJvmLanguage(ext)) return getJvmIcon(ext);

    // Shell Scripts
    if (isShellScript(ext)) return icons.shell;

    // Data and Config files
    if (isDataFile(ext)) return getDataIcon(ext);

    // Documentation file
    if (isDocFile(ext)) return getDocIcon(ext);

    // Media files
    if (isMediaFile(ext)) return getMediaIcon(ext);

    // Beam
    if (isBeamFile(ext)) return getBeamIcon(ext);

    // JVM Languages
    if (isScalaFile(ext)) return icons.scala;
    if (isKotlinFile(ext)) return icons.kotlin;
    if (isClojureFile(ext)) return icons.clojure;

    // Other Languages
    if (isPerlFile(ext)) return icons.perl;
    if (isHaskellFile(ext)) return icons.haskell;
    if (std.mem.eql(u8, ext, ".cr")) return icons.crystal;
    if (std.mem.eql(u8, ext, ".elm")) return icons.elm;
    if (std.mem.eql(u8, ext, ".php")) return icons.php;

    // Editor Files
    if (isVimFile(ext)) return icons.vim;

    // Special Files
    if (std.mem.eql(u8, ext, ".DS_Store")) return icons.apple;
    if (std.mem.eql(u8, ext, ".sqlite")) return icons.sqlite;

    return null;
}

fn isPythonFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".py") or std.mem.eql(u8, ext, ".pyi") or std.mem.eql(u8, ext, ".pyc") or std.mem.eql(u8, ext, ".ipynb");
}

fn isJavascriptFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".mjs") or std.mem.eql(u8, ext, ".ejs") or std.mem.eql(u8, ext, ".cjs") or std.mem.eql(u8, ext, ".jsx");
}

fn isTypescriptFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".ts") or std.mem.eql(u8, ext, ".tsx");
}

fn isWebFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".css") or std.mem.eql(u8, ext, ".sass") or std.mem.eql(u8, ext, ".scss") or std.mem.eql(u8, ext, ".html");
}

fn isCFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".c") or std.mem.eql(u8, ext, ".h");
}

fn isCppFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".cpp") or std.mem.eql(u8, ext, ".hpp") or std.mem.eql(u8, ext, ".c++") or std.mem.eql(u8, ext, ".h++");
}

fn isJavaFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".java") or std.mem.eql(u8, ext, ".class") or std.mem.eql(u8, ext, ".jar") or std.mem.eql(u8, ext, ".jmod");
}

fn isShellScript(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".sh") or std.mem.eql(u8, ext, ".bash") or std.mem.eql(u8, ext, ".zsh") or std.mem.eql(u8, ext, ".fish");
}

fn isDataFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".json") or std.mem.eql(u8, ext, ".toml") or std.mem.eql(u8, ext, ".yaml") or std.mem.eql(u8, ext, ".yml");
}

fn isDocFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".md") or std.mem.eql(u8, ext, ".txt") or std.mem.eql(u8, ext, ".pdf");
}

fn getWebIcon(ext: []const u8) []const u8 {
    if (std.mem.eql(u8, ext, ".css")) return icons.css3;
    if (std.mem.eql(u8, ext, ".sass") or std.mem.eql(u8, ext, ".scss")) return icons.sass;
    if (std.mem.eql(u8, ext, ".html")) return icons.html5;
    return icons.file;
}

fn getDataIcon(ext: []const u8) []const u8 {
    if (std.mem.eql(u8, ext, ".json")) return icons.json;
    if (std.mem.eql(u8, ext, ".toml")) return icons.toml;
    return icons.database;
}

fn isMediaFile(ext: []const u8) []const u8 {
    return isImageFile(ext) or isFontFile(ext);
}

fn getMediaIcon(ext: []const u8) []const u8 {
    if (isImageFile(ext)) return icons.image;
    if (isFontFile(ext)) return icons.font;
    return icons.file;
}

fn getDocIcon(ext: []const u8) []const u8 {
    if (std.mem.eql(u8, ext, ".md")) return icons.markdown;
    if (std.mem.eql(u8, ext, ".pdf")) return icons.pdf;
    return icons.txt;
}

fn isImageFile(ext: []const u8) []const u8 {
    return std.mem.eql(u8, ext, ".jpg") or
        std.mem.eql(u8, ext, ".jpeg") or
        std.mem.eql(u8, ext, ".png") or
        std.mem.eql(u8, ext, ".gif") or
        std.mem.eql(u8, ext, ".svg") or
        std.mem.eql(u8, ext, ".webp") or
        std.mem.eql(u8, ext, ".avif");
}

fn isFontFile(ext: []const u8) []const u8 {
    return std.mem.eql(u8, ext, ".ttf") or
        std.mem.eql(u8, ext, ".otf") or
        std.mem.eql(u8, ext, ".woff") or
        std.mem.eql(u8, ext, ".woff2");
}

fn isBeamFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".ex") or
        std.mem.eql(u8, ext, ".exs") or
        std.mem.eql(u8, ext, ".erl") or
        std.mem.eql(u8, ext, ".hrl");
}

fn getBeamIcon(ext: []const u8) []const u8 {
    if (std.mem.eql(u8, ext, ".ex") or std.mem.eql(u8, ext, ".exs")) return icons.elixir;
    return icons.erlang;
}

fn isClojureFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".clj") or
        std.mem.eql(u8, ext, ".cljs") or
        std.mem.eql(u8, ext, ".cljr") or
        std.mem.eql(u8, ext, ".cljc") or
        std.mem.eql(u8, ext, ".edn");
}

fn isOtherLanguage(ext: []const u8) bool {
    return isPerlFile(ext) or
        isHaskellFile(ext) or
        isCrystalFile(ext) or
        isElmFile(ext) or
        isPhpFile(ext);
}

fn isPerlFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".pl") or std.mem.eql(u8, ext, ".plx");
}

fn isHaskellFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".hs") or std.mem.eql(u8, ext, ".lhs");
}

fn isEditorFile(ext: []const u8) bool {
    return isVimFile(ext);
}

fn isVimFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".viminfo") or
        std.mem.eql(u8, ext, ".vimrc") or
        std.mem.eql(u8, ext, ".vim");
}

/// Checks if file extension belongs to a JVM language
fn isJvmLanguage(ext: []const u8) bool {
    return isJavaFile(ext) or
        isScalaFile(ext) or
        isKotlinFile(ext) or
        isClojureFile(ext);
}

/// Returns appropriate icon for JVM language files
fn getJvmIcon(ext: []const u8) []const u8 {
    if (isJavaFile(ext)) return icons.java;
    if (isScalaFile(ext)) return icons.scala;
    if (isKotlinFile(ext)) return icons.kotlin;
    if (isClojureFile(ext)) return icons.clojure;
    return icons.java; // Default JVM icon
}

fn isScalaFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".scala") or
        std.mem.eql(u8, ext, ".sc");
}

fn isKotlinFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".kt") or
        std.mem.eql(u8, ext, ".kts") or
        std.mem.eql(u8, ext, ".kexe") or
        std.mem.eql(u8, ext, ".klib");
}

fn isCrystalFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".cr") or
        std.mem.eql(u8, ext, ".ecr") or
        std.mem.eql(u8, ext, ".crx");
}

fn isElmFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".elm") or
        std.mem.eql(u8, ext, ".elmi") or
        std.mem.eql(u8, ext, ".elmo");
}

/// Checks for PHP files
fn isPhpFile(ext: []const u8) bool {
    return std.mem.eql(u8, ext, ".php") or
        std.mem.eql(u8, ext, ".php4") or
        std.mem.eql(u8, ext, ".php5") or
        std.mem.eql(u8, ext, ".phtml") or
        std.mem.eql(u8, ext, ".ctp");
}
