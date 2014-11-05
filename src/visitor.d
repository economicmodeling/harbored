/**
 * D Documentation Generator
 * Copyright: © 2014 Economic Modeling Specialists, Intl.
 * Authors: Brian Schott
 * License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt Boost License 1.0)
 */
module visitor;

import ddoc.comments;
import std.algorithm;
import std.d.ast;
import std.d.formatter;
import std.d.lexer;
import std.file;
import std.path;
import std.stdio;
import std.typecons;
import unittest_preprocessor;


/**
 * Generates documentation for a module.
 */
class DocVisitor : ASTVisitor
{
	/**
	 * Params:
	 *     outputDirectory = The directory where files will be written
	 *     macros = Macro definitions used in processing documentation comments
	 *     searchIndex = A file where the search information will be written
	 *     unitTestMapping = The mapping of declaration addresses to their
	 *         documentation unittests
	 *     fileBytes = The source code of the module as a byte array.
	 */
	this(string outputDirectory, string[string] macros, File searchIndex,
		TestRange[][size_t] unitTestMapping, const(ubyte[]) fileBytes)
	{
		this.outputDirectory = outputDirectory;
		this.macros = macros;
		this.searchIndex = searchIndex;
		this.unitTestMapping = unitTestMapping;
		this.fileBytes = fileBytes;
	}

	override void visit(const Module mod)
	{
		import std.array : array;
		import std.algorithm : map;
		import std.path : dirName;
		import std.range : chain, only, join;
		import std.file : mkdirRecurse;
		import std.conv : to;

		if (mod.moduleDeclaration is null)
			return;
		pushAttributes();
		stack = cast(string[]) mod.moduleDeclaration.moduleName.identifiers.map!(a => a.text).array;
		baseLength = stack.length;
		moduleFileBase = chain(only(outputDirectory), stack).buildPath;
		if (!exists(moduleFileBase.dirName()))
			moduleFileBase.dirName().mkdirRecurse();
		File output = File(moduleFileBase ~ ".html", "w");

		location = output.name;
		moduleName = to!string(stack.join("."));
		writeHeader(output, moduleName, baseLength - 1);

		writeBreadcrumbs(output);

		prevComments.length = 1;

		if (mod.moduleDeclaration.comment !is null)
			readAndWriteComment(output, mod.moduleDeclaration.comment, macros,
				prevComments, null, getUnittestDocTuple(mod.moduleDeclaration));

		memberStack.length = 1;

		mod.accept(this);

		memberStack[$ - 1].write(output);

		output.writeln(HTML_END);
		output.close();
	}

	override void visit(const EnumDeclaration ed)
	{
		enum formattingCode = q{
		f.write("enum ", ad.name.text);
		if (ad.type !is null)
		{
			f.write(" : ");
			formatter.format(ad.type);
		}
		};
		visitAggregateDeclaration!(formattingCode, "enums")(ed);
	}

	override void visit(const EnumMember member)
	{
		if (member.comment is null)
			return;
		string summary = readAndWriteComment(File.init, member.comment, macros,
			prevComments, null, getUnittestDocTuple(member));
		memberStack[$ - 1].values ~= Item("#", member.name.text, summary);
	}

	override void visit(const ClassDeclaration cd)
	{
		enum formattingCode = q{
		f.write("class ", ad.name.text);
		if (ad.baseClassList !is null)
			formatter.format(ad.baseClassList);
		if (ad.templateParameters !is null)
			formatter.format(ad.templateParameters);
		if (ad.constraint !is null)
			formatter.format(ad.constraint);
		};
		visitAggregateDeclaration!(formattingCode, "classes")(cd);
	}

	override void visit(const TemplateDeclaration td)
	{
		enum formattingCode = q{
		f.write("template ", ad.name.text);
		if (ad.templateParameters !is null)
			formatter.format(ad.templateParameters);
		if (ad.constraint)
			formatter.format(ad.constraint);
		};
		visitAggregateDeclaration!(formattingCode, "templates")(td);
	}

	override void visit(const StructDeclaration sd)
	{
		enum formattingCode = q{
		f.write("struct ", ad.name.text);
		if (ad.templateParameters)
			formatter.format(ad.templateParameters);
		if (ad.constraint)
			formatter.format(ad.constraint);
		};
		visitAggregateDeclaration!(formattingCode, "structs")(sd);
	}

	override void visit(const InterfaceDeclaration id)
	{
		enum formattingCode = q{
		if (ad.baseClassList !is null)
			formatter.format(ad.baseClassList);
		if (ad.templateParameters !is null)
			formatter.format(ad.templateParameters);
		if (ad.constraint !is null)
			formatter.format(ad.constraint);
		};
		visitAggregateDeclaration!(formattingCode, "interfaces")(id);
	}

	override void visit(const AliasDeclaration ad)
	{
		import std.path : dirSeparator;
		if (ad.comment is null)
			return;
		bool first;
		if (ad.identifierList !is null)
		{
			foreach (name; ad.identifierList.identifiers)
			{
				File f = pushSymbol(name.text, first);
				scope(exit) popSymbol(f);
				writeBreadcrumbs(f);
				string type = writeAliasType(f, name.text, ad.type);
				string summary = readAndWriteComment(f, ad.comment, macros, prevComments);
				memberStack[$ - 2].aliases ~= Item(findSplitAfter(f.name, dirSeparator)[1],
					name.text, summary, type);
			}
		}
		else foreach (initializer; ad.initializers)
		{
			File f = pushSymbol(initializer.name.text, first);
			scope(exit) popSymbol(f);
			writeBreadcrumbs(f);
			string type = writeAliasType(f, initializer.name.text, initializer.type);
			string summary = readAndWriteComment(f, ad.comment, macros, prevComments);
			memberStack[$ - 2].aliases ~= Item(findSplitAfter(f.name, dirSeparator)[1],
				initializer.name.text, summary, type);
		}
	}

	override void visit(const VariableDeclaration vd)
	{
		bool first;
		foreach (const Declarator dec; vd.declarators)
		{
			if (vd.comment is null && dec.comment is null)
				continue;
			File f = pushSymbol(dec.name.text, first);
			scope(exit) popSymbol(f);
			writeBreadcrumbs(f);
			string summary = readAndWriteComment(f,
				dec.comment is null ? vd.comment : dec.comment, macros,
				prevComments);
			memberStack[$ - 2].variables ~= Item(findSplitAfter(f.name, dirSeparator)[1],
				dec.name.text, summary, formatNode(vd.type));
		}
		if (vd.comment !is null && vd.autoDeclaration !is null) foreach (ident; vd.autoDeclaration.identifiers)
		{
			File f = pushSymbol(ident.text, first);
			scope(exit) popSymbol(f);
			writeBreadcrumbs(f);
			string summary = readAndWriteComment(f, vd.comment, macros, prevComments);
			string storageClass;
			foreach (attr; vd.attributes)
			{
				if (attr.storageClass !is null)
					storageClass = str(attr.storageClass.token.type);
			}
			auto i = Item(findSplitAfter(f.name, dirSeparator)[1], ident.text,
				summary, storageClass == "enum" ? null : "auto");
			if (storageClass == "enum")
				memberStack[$ - 2].enums ~= i;
			else
				memberStack[$ - 2].variables ~= i;
		}
	}

	override void visit(const StructBody sb)
	{
		pushAttributes();
		sb.accept(this);
		popAttributes();
	}

	override void visit(const BlockStatement bs)
	{
		pushAttributes();
		bs.accept(this);
		popAttributes();
	}

	override void visit(const Declaration dec)
	{
		attributes[$ - 1] ~= dec.attributes;
		dec.accept(this);
		if (dec.attributeDeclaration is null)
			attributes[$ - 1] = attributes[$ - 1][0 .. $ - dec.attributes.length];
	}

	override void visit(const AttributeDeclaration dec)
	{
		attributes[$ - 1] ~= dec.attribute;
	}

	override void visit(const Constructor cons)
	{
		if (cons.comment is null)
			return;
		bool first;
		File f = pushSymbol("this", first);
		writeFnDocumentation(f, cons, attributes[$ - 1], first);
	}

	override void visit(const FunctionDeclaration fd)
	{
		if (fd.comment is null)
			return;
		bool first;
		File f = pushSymbol(fd.name.text, first);
		writeFnDocumentation(f, fd, attributes[$ - 1], first);
	}

	alias visit = ASTVisitor.visit;

	/// The module name in "package.package.module" format.
	string moduleName;

	/// The path to the HTML file that was generated for the module being
	/// processed.
	string location;

private:

	void visitAggregateDeclaration(string formattingCode, string name, A)(const A ad)
	{
		bool first;
		if (ad.comment is null)
			return;
		File f = pushSymbol(ad.name.text, first);
		if (first)
			writeBreadcrumbs(f);
		else
			f.writeln("<hr/>");
		{
			auto writer = f.lockingTextWriter();
			writer.put(`<pre><code>`);
			auto formatter = new Formatter!(File.LockingTextWriter)(writer);
			scope(exit) formatter.sink = File.LockingTextWriter.init;
			writeAttributes(formatter, writer, attributes[$ - 1]);
			mixin(formattingCode);
			writer.put("\n</code></pre>");
		}
		string summary = readAndWriteComment(f, ad.comment, macros, prevComments,
			null, getUnittestDocTuple(ad));
		mixin(`memberStack[$ - 2].` ~ name ~ ` ~= Item(findSplitAfter(f.name, dirSeparator)[1], ad.name.text, summary);`);
		prevComments.length = prevComments.length + 1;
		ad.accept(this);
		prevComments = prevComments[0 .. $ - 1];
		memberStack[$ - 1].write(f);

		stack = stack[0 .. $ - 1];
		memberStack = memberStack[0 .. $ - 1];
	}

	/**
	 * Params:
	 *     t = The declaration.
	 * Returns: An array of tuples where the first item is the contents of the
	 *     unittest block and the second item is the doc comment for the
	 *     unittest block. This array may be empty.
	 */
	Tuple!(string, string)[] getUnittestDocTuple(T)(const T t)
	{
		immutable size_t index = cast(size_t) (cast(void*) t);
//		writeln("Searching for unittest associated with ", index);
		auto tupArray = index in unitTestMapping;
		if (tupArray is null)
			return [];
//		writeln("Found a doc unit test for ", cast(size_t) &t);
		Tuple!(string, string)[] rVal;
		foreach (tup; *tupArray)
			rVal ~= tuple(cast(string) fileBytes[tup[0] + 2 .. tup[1]], tup[2]);
		return rVal;
	}

	/**
	 *
	 */
	void writeFnDocumentation(Fn)(File f, Fn fn, const(Attribute)[] attrs, bool first)
	{
		auto writer = f.lockingTextWriter();
		if (first)
			writeBreadcrumbs(f);
		else
			writer.put("<hr/>");
		auto formatter = new Formatter!(File.LockingTextWriter)(writer);
		scope(exit) formatter.sink = File.LockingTextWriter.init;
		writer.put(`<pre><code>`);
		writeAttributes(formatter, writer, attrs);
		static if (__traits(hasMember, typeof(fn), "returnType"))
		{
			if (fn.returnType)
			{
				formatter.format(fn.returnType);
				writer.put(" ");
			}
			formatter.format(fn.name);
		}
		else
			writer.put("this");
		if (fn.templateParameters !is null)
			formatter.format(fn.templateParameters);
		if (fn.parameters !is null)
			formatter.format(fn.parameters);
		foreach (a; fn.memberFunctionAttributes)
		{
			writer.put(" ");
			formatter.format(a);
		}
		if (fn.constraint)
		{
			writer.put(" ");
			formatter.format(fn.constraint);
		}
		writer.put("\n</code></pre>");
		string summary = readAndWriteComment(f, fn.comment, macros,
			prevComments, fn.functionBody, getUnittestDocTuple(fn));
		string fdName;
		static if (__traits(hasMember, typeof(fn), "name"))
			fdName = fn.name.text;
		else
			fdName = "this";
		memberStack[$ - 2].functions ~= Item(findSplitAfter(f.name, dirSeparator)[1], fdName, summary);
		prevComments.length = prevComments.length + 1;
		fn.accept(this);
		prevComments = prevComments[0 .. $ - 1];
		stack = stack[0 .. $ - 1];
		memberStack = memberStack[0 .. $ - 1];
	}

	/**
	 * Writes attributes to the given writer using the given formatter.
	 * Params:
	 *     F = The formatter type
	 *     W = The writer type
	 *     formatter = The formatter instance to use
	 *     writer = The writer that will be output to.
	 *     attrs = The attributes to write.
	 */
	void writeAttributes(F, W)(F formatter, W writer, const(Attribute)[] attrs)
	{
		IdType protection;
		if (attrs is null)
			attrs = attributes[$ - 1];
		if (attributes.length > 0) foreach (a; attrs)
		{
			if (isProtection(a.attribute))
				protection = a.attribute;
		}
		switch (protection)
		{
		case tok!"private": writer.put("private "); break;
		case tok!"package": writer.put("package "); break;
		default: writer.put("public "); break;
		}
		if (attributes.length > 0) foreach (a; attrs)
		{
			if (!isProtection(a.attribute))
			{
				formatter.format(a);
				writer.put(" ");
			}
		}
	}

	/**
	 * Formats an AST node to a string
	 */
	static string formatNode(T)(const T t)
	{
		import std.array;
		auto writer = appender!string();
		auto formatter = new Formatter!(typeof(writer))(writer);
		formatter.format(t);
		return writer.data;
	}

	/**
	 * Writes an alias' type to the given file and returns it.
	 * Params:
	 *     f = The file to write to
	 *     name = the name of the alias
	 *     t = the aliased type
	 * Returns: A string reperesentation of the given type.
	 */
	static string writeAliasType(File f, string name, const Type t)
	{
		if (t is null)
			return null;
		f.write(`<pre><code>`);
		f.write("alias ", name, " = ");
		string formatted = formatNode(t);
		f.write(formatted);
		f.writeln(`</code></pre>`);
		return formatted;
	}

	/**
	 * Writes navigation breadcrumbs in HTML format to the given file.
	 */
	void writeBreadcrumbs(File f)
	{
		import std.array : join;
		import std.conv : to;
		import std.range : chain, only;
		f.writeln(`<div class="breadcrumbs">`);
		f.writeln(`<table id="results"></table>`);
		f.writeln(`<input type="search" id="search" placeholder="Search" onkeyup="searchSubmit(this.value, event)"/>`);
		foreach (i; 0 .. stack.length)
		{
			if (i + 1 < stack.length)
			{
				if (i >= baseLength - 1)
				{
					string link = buildPath(chain(stack[0 .. baseLength - 1],
						only(stack[baseLength - 1.. $ - 1].join("."))));
//					writeln(link, ".html");
					f.write(`<a href="`, link, `.html">`);
					f.write(stack[i]);
					f.write(`</a>.`);
				}
				else
				{
					f.write(stack[i]);
					f.write(".");
				}
			}
			else
				f.write(stack[i]);
		}
		f.writeln(`</div>`);
	}

	/**
	 * Params:
	 *     name = The symbol's name
	 *     first = True if this is the first time that pushSymbol has been
	 *         called for this name.
	 *     isFunction = True if the symbol being pushed is a function, false
	 *         otherwise.
	 * Returns: A file that the symbol's documentation should be written to.
	 */
	File pushSymbol(string name, ref bool first)
	{
		import std.array : array, join;
		import std.string : format;
		stack ~= name;
		memberStack.length = memberStack.length + 1;
		string classDocFileName = format("%s.%s.html", moduleFileBase,
			join(stack[baseLength .. $], ".").array);
		string path = (classDocFileName.length > 2 && classDocFileName[0 .. 2] == "./")
				? stripLeadingDirectory(classDocFileName[2 .. $])
				: classDocFileName;
		searchIndex.writefln(`{"%s" : "%s"},`, join(stack, ".").array, path);
		immutable size_t i = memberStack.length - 2;
		assert (i < memberStack.length, "%s %s".format(i, memberStack.length));
		auto p = classDocFileName in memberStack[i].overloadFiles;
		first = p is null;
		if (first)
		{
			first = true;
			auto f = File(classDocFileName, "w");
			memberStack[i].overloadFiles[classDocFileName] = f;
			writeHeader(f, name, baseLength - 1);
			return f;
		}
		else
			return *p;
	}

	void popSymbol(File f)
	{
		f.writeln(HTML_END);
		stack = stack[0 .. $ - 1];
		memberStack = memberStack[0 .. $ - 1];
	}

	void pushAttributes()
	{
		attributes.length = attributes.length + 1;
	}

	void popAttributes()
	{
		attributes = attributes[0 .. $ - 1];
	}

	const(Attribute)[][] attributes;
	Comment[] prevComments;
	size_t baseLength;
	string outputDirectory;
	string moduleFileBase;
	string[] stack;
	string[string] macros;
	Members[] memberStack;
	File searchIndex;
	TestRange[][size_t] unitTestMapping;
	const(ubyte[]) fileBytes;
}

/**
 * Writes HTML header information to the given file.
 * Params:
 *     f = The file to write to
 *     title = The content of the HTML "title" element
 *     depth = The directory depth of the file. This is used for ensuring that
 *         the "base" element is correct so that links resolve properly.
 */
void writeHeader(File f, string title, size_t depth)
{
	f.write(`<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<link rel="stylesheet" type="text/css" href="`);
	foreach (i; 0 .. depth)
		f.write("../");
	f.write(`style.css"/><script src="`);
	foreach (i; 0 .. depth)
		f.write("../");
	f.write(`highlight.pack.js"></script>
<title>`);
	f.write(title);
	f.writeln(`</title>`);
	f.write(`<base href="`);
	foreach (i; 0 .. depth)
		f.write("../");
	f.write(`"/>
<script src="search.js"></script>
</head>
<body>`);
}

/**
 * Writes a doc comment to the given file and returns the summary text.
 * Params:
 *     f = The file to write the comment to
 *     comment = The comment to write
 *     macros = Macro definitions used in processing the comment
 *     prevComments = Previously encountered comments. This is used for handling
 *         "ditto" comments. May be null.
 *     functionBody = A function body used for writing contract information. May
 *         be null.
 *     testdocs = Pairs of unittest bodies and unittest doc comments. May be null.
 * Returns: the summary from the given comment
 */
string readAndWriteComment(File f, string comment, ref string[string] macros,
	Comment[] prevComments = null, const FunctionBody functionBody = null,
	Tuple!(string, string)[] testDocs = null)
{
	import std.d.lexer : unDecorateComment;
	import std.array : appender;
	auto app = appender!string();
	comment.unDecorateComment(app);
//		writeln(comment, " undecorated to ", app.data);
	Comment c = parseComment(app.data, macros);
	if (c.isDitto)
		c = prevComments[$ - 1];
	else if (prevComments.length > 0)
		prevComments[$ - 1] = c;
	writeComment(f, c, functionBody);
	string rVal = "";
	if (c.sections.length && c.sections[0].name == "Summary")
		rVal = c.sections[0].content;
	else
	{
		foreach (section; c.sections)
		{
			if (section.name == "Returns")
				rVal = "Returns: " ~ section.content;
		}
	}
	if (testDocs !is null) foreach (doc; testDocs)
	{
//		writeln("Writing a unittest doc comment");
		import std.string : outdent;
		f.writeln(`<div class="section"><h3>Example</h3>`);
		auto docApp = appender!string();
		doc[1].unDecorateComment(app);
		Comment dc = parseComment(docApp.data, macros);
		writeComment(f, dc);
		f.writeln(`<pre><code>`, outdent(doc[0]), `</code></pre>`);
		f.writeln(`</div>`);
	}
	return rVal;
}

/**
 * Returns: the input string with its first directory removed.
 */
string stripLeadingDirectory(string s)
{
	import std.algorithm : findSplitAfter;
	import std.path : dirSeparator;
	return findSplitAfter(s, dirSeparator)[1];
}

///
unittest
{
	assert (stripLeadingDirectory(`foo/bar/baz`) == `bar/baz`);
	assert (stripLeadingDirectory(`/foo/bar/baz`) == `bar/baz`);
	assert (stripLeadingDirectory(`foo\bar\baz`) == `bar\baz`);
	assert (stripLeadingDirectory(`C:\foo\bar\baz`) == `bar\baz`);
}

private:

void writeComment(File f, Comment comment, const FunctionBody functionBody = null)
{
//		writeln("writeComment: ", comment.sections.length, " sections.");

	size_t i;
	for (i = 0; i < comment.sections.length && (comment.sections[i].name == "Summary"
		|| comment.sections[i].name == "description"); i++)
	{
		f.writeln(`<div class="section">`);
		f.writeln(comment.sections[i].content);
		f.writeln(`</div>`);
	}
	if (functionBody !is null)
		writeContracts(f, functionBody.inStatement, functionBody.outStatement);
	foreach (section; comment.sections[i .. $])
	{
		if (section.name == "Macros")
			continue;
		f.writeln(`<div class="section">`);
		if (section.name != "Summary" && section.name != "Description")
		{
			f.write("<h3>");
			f.write(prettySectionName(section.name));
			f.writeln("</h3>");
		}
		if (section.name == "Params")
		{
			f.writeln(`<table class="params">`);
			foreach (kv; section.mapping)
			{
				f.write(`<tr class="param"><td class="paramName">`);
				f.write(kv[0]);
				f.write(`</td><td class="paramDoc">`);
				f.write(kv[1]);
				f.writeln("</td></tr>");
			}
			f.write("</table>");
		}
		else
		{
			f.writeln(section.content);
		}
		f.writeln(`</div>`);
	}
}

void writeContracts(File f, const InStatement inStatement,
	const OutStatement outStatement)
{
	if (inStatement is null && outStatement is null)
		return;
	f.write(`<div class="section"><h3>Contracts</h3><pre><code>`);
	auto formatter = new Formatter!(File.LockingTextWriter)(f.lockingTextWriter());
	scope(exit) formatter.sink = File.LockingTextWriter.init;
	if (inStatement !is null)
	{
		formatter.format(inStatement);
		if (outStatement !is null)
			f.writeln();
	}
	if (outStatement !is null)
		formatter.format(outStatement);
	f.writeln("</code></pre></div>");
}

string prettySectionName(string sectionName)
{
	switch (sectionName)
	{
	case "See_also": return "See Also";
	case "Params": return "Parameters";
	default: return sectionName;
	}
}

enum HTML_END = `
<script>hljs.initHighlightingOnLoad();</script>
</body>
</html>`;

struct Item
{
	string url;
	string name;
	string summary;
	string type;

	void write(File f)
	{
		f.write(`<tr><td>`);
		if (url == "#")
			f.write(name, `</td>`);
		else
			f.write(`<a href="`, url, `">`, name, `</a></td>`);
		if (type is null)
			f.write(`<td></td><td>`, summary ,`</td></tr>`);
		else
			f.write(`<td><pre><code>`, type, `</code></pre></td><td>`, summary ,`</td></tr>`);
	}
}

struct Members
{
	File[string] overloadFiles;
	Item[] aliases;
	Item[] classes;
	Item[] enums;
	Item[] functions;
	Item[] interfaces;
	Item[] structs;
	Item[] templates;
	Item[] values;
	Item[] variables;

	void write(File f)
	{
		if (aliases.length == 0 && classes.length == 0 && enums.length == 0
			&& functions.length == 0 && interfaces.length == 0
			&& structs.length == 0 && templates.length == 0 && values.length == 0
			&& variables.length == 0)
		{
			return;
		}
		f.writeln(`<div class="section">`);
		if (enums.length > 0)
			write(f, enums, "Enums");
		if (aliases.length > 0)
			write(f, aliases, "Aliases");
		if (variables.length > 0)
			write(f, variables, "Variables");
		if (functions.length > 0)
			write(f, functions, "Functions");
		if (structs.length > 0)
			write(f, structs, "Structs");
		if (interfaces.length > 0)
			write(f, interfaces, "Interfaces");
		if (classes.length > 0)
			write(f, classes, "Classes");
		if (templates.length > 0)
			write(f, templates, "Templates");
		if (values.length > 0)
			write(f, values, "Values");
		f.writeln(`</div>`);
		foreach (f; overloadFiles)
		{
			f.writeln(HTML_END);
			f.close();
		}
	}

private:

	void write(File f, Item[] items, string name)
	{
		f.writeln(`<h3>`, name, `</h3>`);
		f.writeln(`<table>`);
//		f.writeln(`<thead><tr><th>Name</th><th>Summary</th></tr></thead>`);
		foreach (i; items)
			i.write(f);
		f.writeln(`</table>`);
	}
}
