module d.llvm.expression;

import d.llvm.codegen;

import d.ir.expression;
import d.ir.symbol;
import d.ir.type;

import d.exception;
import d.location;

import util.visitor;

import llvm.c.core;

import std.algorithm;
import std.array;
import std.string;

final class ExpressionGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef visit(Expression e) {
		return this.dispatch!(function LLVMValueRef(Expression e) {
			throw new CompileException(e.location, typeid(e).toString() ~ " is not supported");
		})(e);
	}
	
	LLVMValueRef visit(BooleanLiteral bl) {
		return LLVMConstInt(pass.visit(bl.type), bl.value, false);
	}
	
	LLVMValueRef visit(IntegerLiteral!true il) {
		return LLVMConstInt(pass.visit(il.type), il.value, true);
	}
	
	LLVMValueRef visit(IntegerLiteral!false il) {
		return LLVMConstInt(pass.visit(il.type), il.value, false);
	}
	
	LLVMValueRef visit(FloatLiteral fl) {
		return LLVMConstReal(pass.visit(fl.type), fl.value);
	}
	
	// XXX: character types in backend ?
	LLVMValueRef visit(CharacterLiteral cl) {
		return LLVMConstInt(pass.visit(cl.type), cl.value[0], false);
	}
	
	LLVMValueRef visit(NullLiteral nl) {
		return LLVMConstNull(pass.visit(nl.type));
	}
	
	LLVMValueRef visit(StringLiteral sl) {
		return buildDString(sl.value);
	}
	
	private auto handleBinaryOp(alias LLVMBuildOp)(BinaryExpression e) {
		// XXX: should be useless, but order of evaluation of parameters is bugguy.
		auto lhs = visit(e.lhs);
		auto rhs = visit(e.rhs);
		
		return LLVMBuildOp(builder, lhs, rhs, "");
	}
	
	private auto handleBinaryOp(alias LLVMSignedBuildOp, alias LLVMUnsignedBuildOp)(BinaryExpression e) {
		auto t = cast(BuiltinType) e.type.type;
		assert(t);
		
		if(isSigned(t.kind)) {
			return handleBinaryOp!LLVMSignedBuildOp(e);
		} else {
			return handleBinaryOp!LLVMUnsignedBuildOp(e);
		}
	}
	
	private auto handleBinaryOpAssign(alias LLVMBuildOp)(BinaryExpression e) {
		auto lhsPtr = addressOf(e.lhs);
		
		auto lhs = LLVMBuildLoad(builder, lhsPtr, "");
		auto rhs = visit(e.rhs);
		
		auto value = LLVMBuildOp(builder, lhs, rhs, "");
		
		LLVMBuildStore(builder, value, lhsPtr);
		
		return value;
	}
	
	private LLVMValueRef handleComparaison(BinaryExpression e, LLVMIntPredicate predicate) {
		static LLVMIntPredicate workaround;
		
		auto oldWorkaround = workaround;
		scope(exit) workaround = oldWorkaround;
		
		workaround = predicate;
		
		return handleBinaryOp!(function(LLVMBuilderRef builder, LLVMValueRef lhs, LLVMValueRef rhs, const char* name) {
			return LLVMBuildICmp(builder, workaround, lhs, rhs, name);
		})(e);
	}
	
	private LLVMValueRef handleComparaison(BinaryExpression e, LLVMIntPredicate signedPredicate, LLVMIntPredicate unsignedPredicate) {
		auto t = cast(BuiltinType) e.lhs.type.type;
		assert(t);
		
		if(isSigned(t.kind)) {
			return handleComparaison(e, signedPredicate);
		} else {
			return handleComparaison(e, unsignedPredicate);
		}
	}
	
	LLVMValueRef visit(BinaryExpression e) {
		final switch(e.op) with(BinaryOp) {
			case Comma :
				visit(e.lhs);
				return visit(e.rhs);
			
			case Assign :
				auto lhs = addressOf(e.lhs);
				auto rhs = visit(e.rhs);
				
				return LLVMBuildStore(builder, rhs, lhs);
			
			case Add :
				return handleBinaryOp!LLVMBuildAdd(e);
			
			case Sub :
				return handleBinaryOp!LLVMBuildSub(e);
				
			case Concat :
				assert(0, "Not implemented");
			
			case Mul :
				return handleBinaryOp!LLVMBuildMul(e);
			
			case Div :
				return handleBinaryOp!(LLVMBuildSDiv, LLVMBuildUDiv)(e);
			
			case Mod :
				return handleBinaryOp!(LLVMBuildSRem, LLVMBuildURem)(e);
			
			case Pow :
			case AddAssign :
			case SubAssign :
			case ConcatAssign :
			case MulAssign :
			case DivAssign :
			case ModAssign :
			case PowAssign :
			case LogicalOr :
			case LogicalAnd :
			case LogicalOrAssign :
			case LogicalAndAssign :
			case BitwiseOr :
			case BitwiseAnd :
			case BitwiseXor :
			case BitwiseOrAssign :
			case BitwiseAndAssign :
			case BitwiseXorAssign :
				assert(0, "Not implemented");
			
			case Equal :
				return handleComparaison(e, LLVMIntPredicate.EQ);
			
			case NotEqual :
				return handleComparaison(e, LLVMIntPredicate.NE);
			
			case Identical :
				return handleComparaison(e, LLVMIntPredicate.EQ);
			
			case NotIdentical :
				return handleComparaison(e, LLVMIntPredicate.NE);
			
			case In :
			case NotIn :
			case LeftShift :
			case SignedRightShift :
			case UnsignedRightShift :
			case LeftShiftAssign :
			case SignedRightShiftAssign :
			case UnsignedRightShiftAssign :
				assert(0, "Not implemented");
			
			case Greater :
				return handleComparaison(e, LLVMIntPredicate.SGT, LLVMIntPredicate.UGT);
			
			case GreaterEqual :
				return handleComparaison(e, LLVMIntPredicate.SGE, LLVMIntPredicate.UGE);
			
			case Less :
				return handleComparaison(e, LLVMIntPredicate.SLT, LLVMIntPredicate.ULT);
			
			case LessEqual :
				return handleComparaison(e, LLVMIntPredicate.SLE, LLVMIntPredicate.ULE);
			
			case LessGreater :
			case LessEqualGreater :
			case UnorderedLess :
			case UnorderedLessEqual :
			case UnorderedGreater :
			case UnorderedGreaterEqual :
			case Unordered :
			case UnorderedEqual :
				assert(0, "Not implemented");
		}
	}
	
	LLVMValueRef visit(UnaryExpression e) {
		final switch(e.op) with(UnaryOp) {
			case AddressOf :
				return addressOf(e.expr);
			
			case Dereference :
				return LLVMBuildLoad(builder, visit(e.expr), "");
			
			case PreInc :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildAdd(builder, LLVMBuildLoad(builder, ptr, ""), LLVMConstInt(pass.visit(e.type), 1, true), "");
				
				LLVMBuildStore(builder, value, ptr);
				return value;
			
			case PreDec :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildSub(builder, LLVMBuildLoad(builder, ptr, ""), LLVMConstInt(pass.visit(e.type), 1, true), "");
				
				LLVMBuildStore(builder, value, ptr);
				return value;
			
			case PostInc :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildLoad(builder, ptr, "");
				
				LLVMBuildStore(builder, LLVMBuildAdd(builder, value, LLVMConstInt(pass.visit(e.type), 1, true), ""), ptr);
				return value;
			
			case PostDec :
				auto ptr = addressOf(e.expr);
				auto value = LLVMBuildLoad(builder, ptr, "");
				
				LLVMBuildStore(builder, LLVMBuildSub(builder, value, LLVMConstInt(pass.visit(e.type), 1, true), ""), ptr);
				return value;
			
			case Plus :
				return visit(e.expr);
			
			case Minus :
				return LLVMBuildSub(builder, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expr), "");
			
			case Not :
				return LLVMBuildICmp(builder, LLVMIntPredicate.EQ, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expr), "");
			
			case Complement :
				return LLVMBuildXor(builder, visit(e.expr), LLVMConstInt(pass.visit(e.type), -1, true), "");
		}
	}
	
	LLVMValueRef visit(ThisExpression e) {
		return LLVMBuildLoad(builder, addressOf(e), "");
	}
	
	/+
	private auto handleIncrement(bool pre, IncrementExpression)(IncrementExpression e, int step) {
		auto ptr = addressOf(e.expression);
		
		auto preValue = LLVMBuildLoad(builder, ptr, "");
		auto type = e.expression.type;
		
		LLVMValueRef postValue;
		
		if(auto ptrType = cast(PointerType) type) {
			auto indice = LLVMConstInt(LLVMInt64TypeInContext(context), step, true);
			postValue = LLVMBuildInBoundsGEP(builder, preValue, &indice, 1, "");
		} else {
			postValue = LLVMBuildAdd(builder, preValue, LLVMConstInt(pass.visit(type), step, true), "");
		}
		
		LLVMBuildStore(builder, postValue, ptr);
		
		// PreIncrement return the value after it is incremented.
		static if(pre) {
			return postValue;
		} else {
			return preValue;
		}
	}
	
	LLVMValueRef visit(PreIncrementExpression e) {
		return handleIncrement!true(e, 1);
	}
	
	LLVMValueRef visit(PreDecrementExpression e) {
		return handleIncrement!true(e, -1);
	}
	
	LLVMValueRef visit(PostIncrementExpression e) {
		return handleIncrement!false(e, 1);
	}
	
	LLVMValueRef visit(PostDecrementExpression e) {
		return handleIncrement!false(e, -1);
	}
	
	LLVMValueRef visit(UnaryMinusExpression e) {
		return LLVMBuildSub(builder, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expression), "");
	}
	
	LLVMValueRef visit(NotExpression e) {
		// Is it the right way ?
		return LLVMBuildICmp(builder, LLVMIntPredicate.EQ, LLVMConstInt(pass.visit(e.type), 0, true), visit(e.expression), "");
	}
	
	private auto handleLogicalBinary(string operation)(BinaryExpression!operation e) if(operation == "&&" || operation == "||") {
		auto lhs = visit(e.lhs);
		
		auto lhsBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(lhsBB);
		
		static if(operation == "&&") {
			auto rhsBB = LLVMAppendBasicBlockInContext(context, fun, "and_short_circuit");
			auto mergeBB = LLVMAppendBasicBlockInContext(context, fun, "and_merge");
			LLVMBuildCondBr(builder, lhs, rhsBB, mergeBB);
		} else {
			auto rhsBB = LLVMAppendBasicBlockInContext(context, fun, "or_short_circuit");
			auto mergeBB = LLVMAppendBasicBlockInContext(context, fun, "or_merge");
			LLVMBuildCondBr(builder, lhs, mergeBB, rhsBB);
		}
		
		// Emit then
		LLVMPositionBuilderAtEnd(builder, rhsBB);
		
		auto rhs = visit(e.rhs);
		
		// Conclude that block.
		LLVMBuildBr(builder, mergeBB);
		
		// Codegen of then can change the current block, so we put everything in order.
		rhsBB = LLVMGetInsertBlock(builder);
		LLVMMoveBasicBlockAfter(mergeBB, rhsBB);
		LLVMPositionBuilderAtEnd(builder, mergeBB);
		
		//Generate phi to get the result.
		auto phiNode = LLVMBuildPhi(builder, pass.visit(e.type), "");
		
		LLVMValueRef[2] incomingValues;
		incomingValues[0] = lhs;
		incomingValues[1] = rhs;
		
		LLVMBasicBlockRef[2] incomingBlocks;
		incomingBlocks[0] = lhsBB;
		incomingBlocks[1] = rhsBB;
		
		LLVMAddIncoming(phiNode, incomingValues.ptr, incomingBlocks.ptr, incomingValues.length);
		
		return phiNode;
	}
	
	LLVMValueRef visit(LogicalAndExpression e) {
		return handleLogicalBinary(e);
	}
	
	LLVMValueRef visit(LogicalOrExpression e) {
		return handleLogicalBinary(e);
	}
	+/
	LLVMValueRef visit(SymbolExpression e) {
		if(e.symbol.isEnum) {
			return pass.visit(e.symbol);
		} else {
			return LLVMBuildLoad(builder, addressOf(e), "");
		}
	}
	
	LLVMValueRef visit(FieldExpression e) {
		if(e.isLvalue) {
			return LLVMBuildLoad(builder, addressOf(e), "");
		}
		
		return LLVMBuildExtractValue(builder, visit(e.expr), e.field.index, "");
	}
	
	LLVMValueRef visit(MethodExpression e) {
		auto type = cast(DelegateType) e.type.type;
		assert(type);
		
		LLVMValueRef thisValue;
		if(type.context.isRef) {
			thisValue = addressOf(e.expr);
		} else {
			thisValue = visit(e.expr);
		}
		
		LLVMValueRef dg;
		if(auto m = cast(Method) e.method) {
			auto cd = (cast(ClassType) e.expr.type.type).dclass;
			assert(cd, "Virtual dispatch can only be done on classes.");
			
			auto vtbl = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, thisValue, 0, ""), "vtbl");
			auto fun = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, vtbl, m.index, ""), "");
			
			dg = LLVMGetUndef(pass.visit(type));
			
			LLVMDumpValue(dg);
			LLVMDumpValue(fun);
			
			dg = LLVMBuildInsertValue(builder, dg, fun, 0, "");
		} else {
			dg = pass.visit(e.method);
		}
		
		dg = LLVMBuildInsertValue(builder, dg, thisValue, 1, "");
		
		return dg;
	}
	
	LLVMValueRef visit(DelegateExpression e) {
		auto type = cast(DelegateType) e.type.type;
		assert(type);
		
		LLVMValueRef context;
		if(type.context.isRef) {
			context = addressOf(e.context);
		} else {
			context = visit(e.context);
		}
		
		auto dg = LLVMGetUndef(pass.visit(type));
		
		dg = LLVMBuildInsertValue(builder, dg, visit(e.funptr), 0, "");
		dg = LLVMBuildInsertValue(builder, dg, context, 1, "");
		
		return dg;
	}
	/+
	LLVMValueRef visit(NewExpression e) {
		assert(e.arguments.length == 0);
		
		auto type = pass.visit(e.type);
		LLVMValueRef initValue;
		if(auto ct = cast(ClassType) e.type) {
			type = LLVMGetElementType(type);
			
			initValue = getNewInit(ct.dclass);
		}
		
		LLVMValueRef size = LLVMSizeOf(type);
		
		auto alloc = LLVMBuildCall(builder, druntimeGen.getAllocMemory(), &size, 1, "");
		auto ptr = LLVMBuildPointerCast(builder, alloc, LLVMPointerType(type, 0), "");
		
		if(initValue) {
			initValue = LLVMBuildLoad(builder, initValue, "");
			LLVMBuildStore(builder, initValue, ptr);
		}
		
		return ptr;
	}
	+/
	LLVMValueRef visit(IndexExpression e) {
		return LLVMBuildLoad(builder, addressOf(e), "");
	}
	/+
	LLVMValueRef visit(SliceExpression e) {
		assert(e.first.length == 1 && e.second.length == 1);
		
		auto indexed = addressOf(e.indexed);
		auto first = LLVMBuildZExt(builder, visit(e.first[0]), LLVMInt64TypeInContext(context), "");
		auto second = LLVMBuildZExt(builder, visit(e.second[0]), LLVMInt64TypeInContext(context), "");
		
		// To ensure bound check. Before ptr calculation for optimization purpose.
		computeIndice(e.location, e.indexed.type, indexed, second);
		
		auto length = LLVMBuildSub(builder, second, first, "");
		auto ptr = computeIndice(e.location, e.indexed.type, indexed, first);
		
		auto slice = LLVMGetUndef(pass.visit(e.type));
		
		slice = LLVMBuildInsertValue(builder, slice, length, 0, "");
		slice = LLVMBuildInsertValue(builder, slice, ptr, 1, "");
		
		return slice;
	}
	+/
	
	LLVMValueRef visit(CastExpression e) {
		auto value = visit(e.expr);
		auto type = pass.visit(e.type);
		
		final switch(e.kind) with(CastKind) {
			case Invalid :
				assert(0, "Invalid cast");
			
			case IntegralToBool :
				assert(0, "Integral to bool cast not implemented");
			
			case Trunc :
				return LLVMBuildTrunc(builder, value, type, "");
			
			case Pad :
				auto bt = cast(BuiltinType) e.expr.type.type;
				assert(bt);
				
				auto k = bt.kind;
				
				if(k == TypeKind.Bool || !isSigned(k)) {
					return LLVMBuildZExt(builder, value, type, "");
				} else {
					return LLVMBuildSExt(builder, value, type, "");
				}
			
			case Bit :
				return LLVMBuildBitCast(builder, value, type, "");
			
			case Qual :
			case Exact :
				return value;
		}
	}
	
	LLVMValueRef visit(CallExpression c) {
		auto callee = visit(c.callee);
		
		ParamType[] paramTypes;
		LLVMValueRef[] args;
		uint firstarg;
		
		if(auto type = cast(DelegateType) c.callee.type.type) {
			paramTypes = type.paramTypes;
			
			auto fun = LLVMBuildExtractValue(builder, callee, 0, "");
			
			firstarg++;
			args.length = c.arguments.length + 1;
			args[0] = LLVMBuildExtractValue(builder, callee, 1, "");
			
			callee = fun;
		} else if(auto type = cast(FunctionType) c.callee.type.type) {
			paramTypes = type.paramTypes;
			args.length = c.arguments.length;
		} else {
			assert(0, "You can only call function and delegates !");
		}
		
		uint i;
		foreach(t; paramTypes) {
			if(t.isRef) {
				args[i + firstarg] = addressOf(c.arguments[i]);
			} else {
				args[i + firstarg] = visit(c.arguments[i]);
			}
			
			i++;
		}
		
		// Handle variadic functions.
		while(i < c.arguments.length) {
			args[i + firstarg] = visit(c.arguments[i]);
			i++;
		}
		
		return LLVMBuildCall(builder, callee, args.ptr, cast(uint) args.length, "");
	}
	/+
	private auto handleTuple(bool isCT)(TupleExpressionImpl!isCT e) {
		auto fields = e.values.map!(v => visit(v)).array();
		
		// Hack around the difference between struct and named struct in LLVM.
		auto type = pass.visit(e.type);
		return LLVMConstNamedStruct(type, fields.ptr, cast(uint) fields.length);
	}
	
	LLVMValueRef visit(TupleExpression e) {
		return handleTuple(e);
	}
	
	LLVMValueRef visit(CompileTimeTupleExpression e) {
		return handleTuple(e);
	}
	+/
	LLVMValueRef visit(VoidInitializer v) {
		return LLVMGetUndef(pass.visit(v.type));
	}
	/+
	LLVMValueRef visit(AssertExpression e) {
		auto test = visit(e.condition);
		
		auto testBB = LLVMGetInsertBlock(builder);
		auto fun = LLVMGetBasicBlockParent(testBB);
		
		auto failBB = LLVMAppendBasicBlockInContext(context, fun, "assert_fail");
		auto successBB = LLVMAppendBasicBlockInContext(context, fun, "assert_success");
		
		auto br = LLVMBuildCondBr(builder, test, successBB, failBB);
		
		// We assume that assert fail is unlikely.
		LLVMSetMetadata(br, profKindID, unlikelyBranch);
		
		// Emit assert call
		LLVMPositionBuilderAtEnd(builder, failBB);
		
		LLVMValueRef args[3];
		args[1] = buildDString(e.location.source.filename);
		args[2] = LLVMConstInt(LLVMInt32TypeInContext(context), e.location.line, false);
		
		if(e.message) {
			args[0] = visit(e.message);
			LLVMBuildCall(builder, druntimeGen.getAssertMessage(), args.ptr, 3, "");
		} else {
			LLVMBuildCall(builder, druntimeGen.getAssert(), &args[1], 2, "");
		}
		
		// Conclude that block.
		LLVMBuildUnreachable(builder);
		
		// Now continue regular execution flow.
		LLVMPositionBuilderAtEnd(builder, successBB);
		
		// XXX: should figure out what is the right value to return.
		return null;
	}
	+/
}

final class AddressOfGen {
	private CodeGenPass pass;
	alias pass this;
	
	this(CodeGenPass pass) {
		this.pass = pass;
	}
	
	LLVMValueRef visit(Expression e) {
		return this.dispatch(e);
	}
	
	LLVMValueRef visit(SymbolExpression e) {
		assert(!e.symbol.isEnum, "enum have no address.");
		
		return pass.visit(e.symbol);
	}
	
	LLVMValueRef visit(FieldExpression e) {
		auto ptr = visit(e.expr);
		
		// Pointer auto dereference in D.
		while(1) {
			auto pointed = LLVMGetElementType(LLVMTypeOf(ptr));
			auto kind = LLVMGetTypeKind(pointed);
			if(kind != LLVMTypeKind.Pointer) {
				assert(kind == LLVMTypeKind.Struct);
				break;
			}
			
			ptr = LLVMBuildLoad(builder, ptr, "");
		}
		
		return LLVMBuildStructGEP(builder, ptr, e.field.index, "");
	}
	
	LLVMValueRef visit(ThisExpression e) {
		// FIXME: this is completely work, but will do the trick for now.
		return LLVMGetFirstParam(LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder)));
	}
	/+
	LLVMValueRef visit(DereferenceExpression e) {
		return pass.visit(e.expression);
	}
	
	LLVMValueRef visit(BitCastExpression e) {
		return LLVMBuildBitCast(builder, visit(e.expression), LLVMPointerType(pass.visit(e.type), 0), "");
	}
	
	LLVMValueRef computeIndice(Location location, Type indexedType, LLVMValueRef indexed, LLVMValueRef indice) {
		if(typeid(indexedType) is typeid(SliceType)) {
			auto length = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, indexed, 0, ""), ".length");
			
			auto condition = LLVMBuildICmp(builder, LLVMIntPredicate.ULT, LLVMBuildZExt(builder, indice, LLVMInt64TypeInContext(context), ""), length, ".boundCheck");
			auto fun = LLVMGetBasicBlockParent(LLVMGetInsertBlock(builder));
			
			auto failBB = LLVMAppendBasicBlockInContext(context, fun, "arrayBoundFail");
			auto okBB = LLVMAppendBasicBlockInContext(context, fun, "arrayBoundOK");
			
			auto br = LLVMBuildCondBr(builder, condition, okBB, failBB);
			
			// We assume that bound check fail is unlikely.
			LLVMSetMetadata(br, profKindID, unlikelyBranch);
			
			// Emit bound check fail code.
			LLVMPositionBuilderAtEnd(builder, failBB);
			
			LLVMValueRef args[2];
			args[0] = buildDString(location.source.filename);
			args[1] = LLVMConstInt(LLVMInt32TypeInContext(context), location.line, false);
			
			LLVMBuildCall(builder, druntimeGen.getArrayBound(), args.ptr, cast(uint) args.length, "");
			
			LLVMBuildUnreachable(builder);
			
			// And continue regular program flow.
			LLVMPositionBuilderAtEnd(builder, okBB);
			
			indexed = LLVMBuildLoad(builder, LLVMBuildStructGEP(builder, indexed, 1, ""), ".ptr");
		} else if(typeid(indexedType) is typeid(PointerType)) {
			indexed = LLVMBuildLoad(builder, indexed, "");
		} else if(typeid(indexedType) is typeid(StaticArrayType)) {
			auto indices = [LLVMConstInt(LLVMInt64TypeInContext(context), 0, false), indice];
			
			return LLVMBuildInBoundsGEP(builder, indexed, indices.ptr, 2, "");
		} else {
			assert(0, "Don't know how to index this.");
		}
		
		return LLVMBuildInBoundsGEP(builder, indexed, &indice, 1, "");
	}
	
	LLVMValueRef visit(IndexExpression e) {
		assert(e.arguments.length == 1);
		
		auto indexed = visit(e.indexed);
		auto indice = pass.visit(e.arguments[0]);
		
		return computeIndice(e.location, e.indexed.type, indexed, indice);
	}
	+/
}
