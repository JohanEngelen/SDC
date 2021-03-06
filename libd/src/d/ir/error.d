module d.ir.error;

import d.context.location;
import d.context.name;

import d.ir.expression;
import d.ir.statement;
import d.ir.symbol;

class CompileError {
	Location location;
	string message;
	
	void[StorageSize!ErrorSymbol] symStorage;
	void[StorageSize!ErrorExpression] exprStorage;
	
public:
	this(Location location, string message) {
		this.location = location;
		this.message = message;
		
		import std.conv;
		symStorage.emplace!ErrorSymbol(this);
		exprStorage.emplace!ErrorExpression(this);
	}
	
	string toString(const ref NameManager nm) const {
		return message;
	}
	
final:
	@property
	auto symbol() inout {
		return cast(inout(ErrorSymbol)) symStorage.ptr;
	}
	
	@property
	auto expression() inout {
		return cast(inout(ErrorExpression)) exprStorage.ptr;
	}
	
	@property
	auto type() {
		import d.ir.type;
		return Type.get(this);
	}
}

auto getError(T)(T t, Location location, string msg) {
	import d.ir.type;
	static if (is(T : Expression)) {
		if (auto e = cast(ErrorExpression) t) {
			return e.error;
		}
	} else static if (is(T : Symbol)) {
		if (auto e = cast(ErrorSymbol) t) {
			return e.error;
		}
	} else static if (is(T : Type)) {
		if (t.kind == TypeKind.Error) {
			return t.error;
		}
	} else {
		static assert(0, "Unepxected " ~ typeid(t).toString());
	}
	
	return new CompileError(location, msg);
}

final:
/**
 * An Error occured but an Expression is expected.
 * Useful for speculative compilation.
 */
class ErrorExpression : CompileTimeExpression {
// private:
	this(CompileError error) {
		import d.ir.type;
		super(error.location, Type.get(error));
	}
	
	invariant() {
		import d.ir.type;
		assert(type.kind == TypeKind.Error);
	}
	
public:
	@property
	auto error() {
		return type.error;
	}
	
	override string toString(const ref NameManager nm) const {
		return type.toString(nm);
	}
}

/**
 * An Error occured but a Symbol is expected.
 * Useful for speculative compilation.
 */
class ErrorSymbol : Symbol {
	CompileError error;
	
// private:
	this(CompileError error) {
		super(error.location, BuiltinName!"");
		
		this.error = error;
		step = Step.Processed;
	}
	
public:
	override string toString(const ref NameManager nm) const {
		return "__error__(" ~ error.toString(nm) ~ ")";
	}
}

private:
template StorageSize(T) {
	enum InstanceSize = __traits(classInstanceSize, T);
	enum PtrSize = ((InstanceSize - 1) / size_t.sizeof) + 1;
	enum StorageSize = PtrSize * size_t.sizeof;
}
