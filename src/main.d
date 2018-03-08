/**
 * D Documentation Generator
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */
module main;

import std.algorithm;
import std.array;
import std.conv;
import dparse.ast;
import dparse.lexer;
import dparse.parser;
import std.file;
import std.getopt;
import std.path;
import std.stdio;
import visitor;
import unittest_preprocessor;
import macros;
import tocbuilder;
import ddoc.comments;

int main(string[] args)
{
	version(unittest)
		return 0;

	string[] macroFiles;
	string[] excludes;
	string outputDirectory;
	bool help;
	string indexContent;

	getopt(args, "m|macros", &macroFiles, "o|output-directory", &outputDirectory,
		"h|help", &help, "i|index", &indexContent, "e|exclude", &excludes);

	if (help)
	{
		writeln(helpString);
		return 0;
	}

	string[string] macros;
	try
		macros = readMacros(macroFiles);
	catch (Exception e)
	{
		stderr.writeln(e.msg);
		return 1;
	}

	if (outputDirectory is null)
		outputDirectory = "doc";

	generateDocumentation(outputDirectory, indexContent, macros, args[1 .. $]);

	return 0;
}

string[string] readMacros(const string[] macroFiles)
{
	import ddoc.macros : DEFAULT_MACROS;
	string[string] rVal;
	foreach (k, v; DEFAULT_MACROS)
		rVal[k] = v;
	foreach (mf; macroFiles)
		readMacroFile(mf, rVal);
	return rVal;
}

void generateDocumentation(string outputDirectory, string indexContent,
	string[string] macros, string[] args)
{
	string[] files = getFilesToProcess(args);
	import std.stdio : stderr, File;
	stderr.writeln("Writing documentation to ", outputDirectory);

	mkdirRecurse(outputDirectory);

	{
		File css = File(buildPath(outputDirectory, "style.css"), "w");
		css.write(stylecss);
		File js = File(buildPath(outputDirectory, "highlight.pack.js"), "w");
		js.write(hljs);
		File index = File(buildPath(outputDirectory, "index.html"), "w");
		index.write(indexhtml);
		if (indexContent !is null)
		{
			File frontPage = File(buildPath(outputDirectory, "index_content.html"), "w");
			writeHeader(frontPage, "Index", 0);
			frontPage.writeln(`<div class="breadcrumbs">
<table id="results"></table>
<input type="search" id="search" placeholder="Search" onkeyup="searchSubmit(this.value, event)"/>
Main Page</div>`);
			File indexContentFile = File(indexContent);
			ubyte[] indexContentBytes = new ubyte[cast(uint) indexContentFile.size];
			indexContentFile.rawRead(indexContentBytes);
			Comment[] prev;
			readAndWriteComment(frontPage, cast(string) indexContentBytes, macros, prev);
			frontPage.writeln(`
	</body>
</html>`);
		}

	}

	File search = File(buildPath(outputDirectory, "search.js"), "w");
	search.writeln(`"use strict";`);
	search.writeln(`var items = [`);

	string[] modules;
	string[string] moduleMap;

	foreach (f; files)
	{
		writeln("Generating documentation for ", f);
		string moduleName;
		string location;
		try
		{
			writeDocumentation(outputDirectory, f, macros, moduleName, location, search);
			if (moduleName != "")
			{
				immutable string path = stripLeadingDirectory(location, outputDirectory);
				modules ~= moduleName;
				moduleMap[moduleName] = path;
			}
		}
		catch (Exception e)
		{
			stderr.writeln("Could not generate documentation for ", f, ": ", e.msg);
		}
	}
	search.writeln(`];`);
	search.writeln(searchjs);

	File toc = File(buildPath(outputDirectory, "toc.html"), "w");
	toc.writeln(`<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<style type="text/css">
html {
	background-color: #eee;
    padding: 0;
    margin: 0;
}

body {
    padding: 0;
    margin: 0;
}

ul {
    font-family: sans;
    list-style: none;
    padding: 0 0 0 1.5em;
}
ul ul {
	display: none;
}
span {
	cursor: pointer;
	font-weight: bold;
}

.expanded::before {
	content: "▼ ";
}

span::before {
	content: "▶ ";
}
</style>
<script type="text/javascript">
"use strict";
function toggleChildren(t) {
	var c = t.nextElementSibling;
	if (t.className != "expanded" && (c.style.display === "" || c.style.display === "none")) {
		c.style.display = "list-item";
		t.className = "expanded";
	} else {
		c.style.display = "none";
		t.className = "";
	}
}
</script>
</head>
<body>`);
	toc.writeln(`<ul>`);

	sort(modules);
	buildTree(modules, moduleMap).each!(a => a.write(toc));
	toc.writeln(`</ul></body></html>`);
}

/// Creates documentation for the module at the given path
void writeDocumentation(string outputDirectory, string path,
	string[string] macros, ref string moduleName, ref string location,
	File search)
{
	import dparse.rollback_allocator : RollbackAllocator;

	LexerConfig config;
	config.fileName = path;
	config.stringBehavior = StringBehavior.source;

	File f = File(path);
	ubyte[] fileBytes = uninitializedArray!(ubyte[])(to!size_t(f.size));
	f.rawRead(fileBytes);
	StringCache cache = StringCache(1024 * 4);
	auto tokens = getTokensForParser(fileBytes, config, &cache).array;
	RollbackAllocator rba;
	void doNothing(string, size_t, size_t, string, bool) {}
	Module m = parseModule(tokens, path, &rba, &doNothing);
	const TestRange[][size_t] unitTestMapping = getUnittestMap(m);
	DocVisitor visitor = new DocVisitor(outputDirectory, macros, search,
		unitTestMapping, fileBytes);
	visitor.visit(m);
	moduleName = visitor.moduleName;
	location = visitor.location;
}

string[] getFilesToProcess(string[] args)
{
	auto files = appender!(string[])();
	foreach (arg; args)
	{
		if (isDir(arg)) foreach (string fileName; dirEntries(arg, "*.{d,di}", SpanMode.depth))
			files.put(expandTilde(fileName));
		else if (isFile(arg))
			files.put(expandTilde(arg));
		else
			stderr.writeln("Could not open `", arg, "`");
	}
	return files.data;
}

enum helpString = `
Generates documentation for D source code.

Usage:
    harbored [Options] file.d
    harbored [Options] directory1/ directory2/ ...

Options:
    --macros | -m MACRO_FILE
        Specifies a macro definition file

    --output-directory | -o DIR
        Writes the generated documentation to the given directory. If this
        option is not specified, documentation will be written to a folder
        called "doc" in the current directory.

    --exclude | -e MODULE_NAME
        Exclude the given module or package from the generated documentation.
        By default no modules or packages will be excluded unless they do not
        contain a module declaration.

    --index | -i DDOC_FILE
        Use DDOC_FILE as the content of the index.html page. By default this
        page will be blank.

    --help | -h
        Prints this message.
`;

immutable string hljs = import("highlight.pack.js");
immutable string stylecss = import("style.css");
immutable string indexhtml = import("index.html");
immutable string searchjs = import("search.js");
