module d.context.name;

struct Name {
private:
	uint id;
	
	this(uint id) {
		this.id = id;
	}
	
public:
	string toString(const ref NameManager nm) const {
		return nm.names[id];
	}
	
	immutable(char)* toStringz(const ref NameManager nm) const {
		auto s = nm.names[id];
		assert(s.ptr[s.length] == '\0', "Expected a zero terminated string");
		return s.ptr;
	}
	
	@property
	bool isEmpty() const {
		return this == BuiltinName!"";
	}
	
	@property
	bool isReserved() const {
		return id < (Names.length - Prefill.length);
	}
	
	@property
	bool isDefined() const {
		return id != 0;
	}
}

template BuiltinName(string name) {
	private enum id = Lookups.get(name, uint.max);
	static assert(id < uint.max, name ~ " is not a builtin name.");
	enum BuiltinName = Name(id);
}

struct NameManager {
private:
	string[] names;
	uint[string] lookups;

	// Make it non copyable.
	@disable this(this);

package:
	static get() {
		return NameManager(Names, Lookups);
	}

public:
	auto getName(const(char)[] str) {
		if (auto id = str in lookups) {
			return Name(*id);
		}
		
		// As we are cloning, make sure it is 0 terminated as to pass to C.
		import std.string;
		auto s = str.toStringz()[0 .. str.length];
		
		// Make sure we do not keep around slice of potentially large input.
		scope(exit) assert(str.ptr !is s.ptr, s);
		
		auto id = lookups[s] = cast(uint) names.length;
		names ~= s;
		
		return Name(id);
	}
	
	void dump() {
		foreach(s; names) {
			import std.stdio;
			writeln(lookups[s], "\t=> ", s);
		}
	}
}

private:

enum Reserved = ["__ctor", "__dtor", "__vtbl"];

enum Prefill = [
	// Linkages
	"C", "D", "C++", "Windows", "System", "Pascal", "Java",
	// Version
	"SDC", "D_LP64", "X86_64", "linux", "OSX", "Posix",
	// Generated
	"init", "length", "max", "min", "ptr", "sizeof", "alignof",
	// Scope
	"exit", "success", "failure",
	// Main
	"main", "_Dmain",
	// Defined in object
	"object", "size_t", "ptrdiff_t", "string",
	"Object",
	"TypeInfo", "ClassInfo",
	"Throwable", "Exception", "Error",
	// Attribute
	"property", "safe", "trusted", "system", "nogc",
	// druntime
	"_d_assert", "_d_assert_msg", "_d_arraybounds", "_d_allocmemory",
	// Runtime
	"__sd_class_downcast",
	"__sd_eh_throw",
	"__sd_eh_personality",
	"__sd_array_concat",
	// Generated symbols
	"__dg",
	"__lambda",
	"__ctx",
];

auto getNames() {
	import d.lexer;
	
	auto identifiers = [""];
	foreach(k, _; getOperatorsMap()) {
		identifiers ~= k;
	}
	
	foreach(k, _; getKeywordsMap()) {
		identifiers ~= k;
	}
	
	return identifiers ~ Reserved ~ Prefill;
}

enum Names = getNames();

static assert(Names[0] == "");

auto getLookups() {
	// XXX: DMD zero terminate here, but I'd like to not rely on it :/
	uint[string] lookups;
	foreach(uint i, id; Names) {
		lookups[id] = i;
	}
	
	return lookups;
}

enum Lookups = getLookups();
