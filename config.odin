package odin_html_docs

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import doc "core:odin/doc-format"

Config :: struct {
	hide_base:    bool,
	hide_core:    bool,
	_collections: map[string]Collection `json:"collections"`,
	url_prefix:   string,
	domain:       string, // Used to determine if a link is external, to add `target="_blank"`.


	// -- Start non configurable --
	header:   ^doc.Header,
	files:    []doc.File,
	pkgs:     []doc.Pkg,
	entities: []doc.Entity,
	types:    []doc.Type,

	// Maps are unordered, we want an order to places where it matters, like the homepage.
	// Why is 'collections' not a slice? Because the JSON package overwrites the full slice when
	// you unmarshal into it, with a map, when unmarshalling into it, the entries are added to existing ones.
	collections: [dynamic]^Collection,

	pkg_to_collection:   map[^doc.Pkg]^Collection,
	pkg_to_header:       map[^doc.Pkg]^doc.Header,
	handled_packages:    map[string]int,

	pkgs_line_docs:     map[string]string,

	entity_to_pkg:      map[^doc.Entity]^doc.Pkg,
}

Collection :: struct {
	name:            string,
	source_url:      string,
	base_url:        string,
	root_path:       string,
	license:         Collection_License,
	home:            Collection_Home,
	// Hides the collection from navigation but can still be
	// linked to.
	hidden:          bool,

	// -- Start non configurable --
	root:            ^Dir_Node,
	pkgs:            map[string]^doc.Pkg,
	pkg_to_path:     map[^doc.Pkg]string,
	pkg_entries_map: map[^doc.Pkg]Pkg_Entries,
}

Collection_License :: struct {
	text: string,
	url:  string,
}

Collection_Home :: struct {
	title:        Maybe(string),
	description:  Maybe(string),
	embed_readme: Maybe(string),
}

Collection_Error :: string

collection_validate :: proc(c: ^Collection) -> Maybe(Collection_Error) {
	if c.name == "" {
		return "collection requires the key \"name\" to be set to the name of the collection, example: \"core\""
	}
	if c.source_url == "" {
		return "collection requires the key \"source_url\" to be set to a URL that points to the root of collection on a website like GitHub, example: \"https://github.com/odin-lang/Odin/tree/master/core\""
	}
	if c.base_url == "" {
		return "collection requires the key \"base_url\" to be set to the relative URL to your collection, example: \"/core\""
	}
	if c.license.text == "" {
		return "collection requires the key \"license.text\" to be set to the name of the license of your collection, example: \"BSD-3-Clause\""
	}
	if c.license.url == "" {
		return "collection requires the key \"license.url\" to be set to a URL that points to the license of your collection, example: \"https://github.com/odin-lang/Odin/tree/master/LICENSE\""
	}
	if c.root_path == "" {
		return "collection requires the key \"root_path\" to be set to part of the path of all packages in the collection that should be removed, you can use $ODIN_ROOT, or $PWD as variables"
	}

	if strings.contains_rune(c.name, '/') {
		return "collection name should not contain slashes"
	}

	if !strings.has_prefix(c.base_url, "/") {
		return "collection base_url should start with a slash"
	}

	c.base_url = strings.trim_suffix(c.base_url, "/")
	c.source_url = strings.trim_suffix(c.source_url, "/")

	new_root_path := config_do_replacements(c.root_path)
	delete(c.root_path)
	c.root_path = new_root_path

	if rm, ok := c.home.embed_readme.?; ok {
		new_rm := config_do_replacements(rm)
		delete(rm)
		c.home.embed_readme = new_rm
	}

	return nil
}

config_default :: proc() -> (c: Config) {
	err := json.unmarshal(#load("resources/odin-doc.json"), &c)
	fmt.assertf(err == nil, "Unable to load default config: %v", err)
	config_sort_collections(&c)
	return
}

config_merge_from_file :: proc(c: ^Config, file: string) -> (file_ok: bool, err: json.Unmarshal_Error) {
	data: []byte
	data, file_ok = os.read_entire_file_from_filename(file)
	if !file_ok do return

	err = json.unmarshal(data, c)

	for _, &collection in c._collections {
		if c.hide_core && (collection.name == "core" || collection.name == "vendor") {
			collection.hidden = true
		}

		if c.hide_base && (collection.name == "base") {
			collection.hidden = true
		}

		if c.url_prefix != "" {
			new_base_url := strings.concatenate({c.url_prefix, collection.base_url})
			delete(collection.base_url)
			collection.base_url = new_base_url
		}
	}

	config_sort_collections(c)
	return
}

config_sort_collections :: proc(c: ^Config) {
	clear(&c.collections)
	for _, &collection in c._collections {
		append(&c.collections, &collection)
	}

	slice.sort_by(
		c.collections[:],
		proc(a, b: ^Collection) -> bool { return a.name < b.name },
	)
}

// Replaces $ODIN_ROOT with ODIN_ROOT, and turns it into an absolute path.
config_do_replacements :: proc(path: string) -> string {
	res, allocated := strings.replace(path, "$ODIN_ROOT", ODIN_ROOT, 1)

	abs, ok := filepath.abs(res)
	if !ok {
		log.warnf("Could not resolve absolute path from %q", res)
		return res
	}

	if allocated do delete(res)

	// The `odin doc` spits paths out the other way.
	when ODIN_OS == .Windows {
		replaced, replace_was_alloc := strings.replace_all(abs, "\\", "/")
		if replace_was_alloc do delete(abs)
		return replaced
	} else {
		return abs
	}
}
