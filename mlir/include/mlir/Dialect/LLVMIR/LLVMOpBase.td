//===-- LLVMOpBase.td - LLVM IR dialect shared definitions -*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains shared definitions for the LLVM IR dialect and its
// subdialects.
//
//===----------------------------------------------------------------------===//

#ifndef LLVMIR_OP_BASE
#define LLVMIR_OP_BASE

include "mlir/IR/OpBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

//===----------------------------------------------------------------------===//
// LLVM Dialect.
//===----------------------------------------------------------------------===//

def LLVM_Dialect : Dialect {
  let name = "llvm";
  let cppNamespace = "::mlir::LLVM";

  let hasRegionArgAttrVerify = 1;
  let hasOperationAttrVerify = 1;
  let extraClassDeclaration = [{
    /// Name of the data layout attributes.
    static StringRef getDataLayoutAttrName() { return "llvm.data_layout"; }
    static StringRef getAlignAttrName() { return "llvm.align"; }
    static StringRef getNoAliasAttrName() { return "llvm.noalias"; }

    /// Verifies if the given string is a well-formed data layout descriptor.
    /// Uses `reportError` to report errors.
    static LogicalResult verifyDataLayoutString(
        StringRef descr, llvm::function_ref<void (const Twine &)> reportError);
  }];
}

//===----------------------------------------------------------------------===//
// LLVM dialect type constraints.
//===----------------------------------------------------------------------===//

// LLVM dialect type.
def LLVM_Type : DialectType<LLVM_Dialect,
                            CPred<"$_self.isa<::mlir::LLVM::LLVMType>()">,
                            "LLVM dialect type">;

// Type constraint accepting LLVM integer types.
def LLVM_AnyInteger : Type<
  CPred<"$_self.isa<::mlir::LLVM::LLVMIntegerType>()">,
  "LLVM integer type">;

// Type constraints accepting LLVM integer type of a specific width.
class LLVM_IntBase<int width> :
    Type<And<[
        LLVM_AnyInteger.predicate,
        CPred<"$_self.cast<::mlir::LLVM::LLVMIntegerType>().getBitWidth() == "
              # width>]>,
        "LLVM " # width # "-bit integer type">,
    BuildableType<
        "::mlir::LLVM::LLVMIntegerType::get($_builder.getContext(), "
        # width # ")">;

def LLVM_i1 : LLVM_IntBase<1>;
def LLVM_i8 : LLVM_IntBase<8>;
def LLVM_i32 : LLVM_IntBase<32>;

// Type constraint accepting LLVM primitive types, i.e. all types except void
// and function.
def LLVM_PrimitiveType : Type<
  And<[LLVM_Type.predicate,
       CPred<"!$_self.isa<::mlir::LLVM::LLVMVoidType, "
                         "::mlir::LLVM::LLVMFunctionType>()">]>,
  "primitive LLVM type">;

// Type constraint accepting any LLVM floating point type.
def LLVM_AnyFloat : Type<
  CPred<"$_self.isa<::mlir::LLVM::LLVMBFloatType, "
                   "::mlir::LLVM::LLVMHalfType, "
                   "::mlir::LLVM::LLVMFloatType, "
                   "::mlir::LLVM::LLVMDoubleType, "
                   "::mlir::LLVM::LLVMFP128Type, "
                   "::mlir::LLVM::LLVMX86FP80Type>()">,
  "floating point LLVM type">;

// Type constraint accepting any LLVM pointer type.
def LLVM_AnyPointer : Type<CPred<"$_self.isa<::mlir::LLVM::LLVMPointerType>()">,
                          "LLVM pointer type">;

// Type constraint accepting LLVM pointer type with an additional constraint
// on the element type.
class LLVM_PointerTo<Type pointee> : Type<
  And<[LLVM_AnyPointer.predicate,
       SubstLeaves<
         "$_self",
         "$_self.cast<::mlir::LLVM::LLVMPointerType>().getElementType()",
         pointee.predicate>]>,
  "LLVM pointer to " # pointee.description>;

// Type constraint accepting any LLVM structure type.
def LLVM_AnyStruct : Type<CPred<"$_self.isa<::mlir::LLVM::LLVMStructType>()">,
                         "LLVM structure type">;

// Type constraint accepting opaque LLVM structure type.
def LLVM_OpaqueStruct : Type<
  And<[LLVM_AnyStruct.predicate,
       CPred<"$_self.cast<::mlir::LLVM::LLVMStructType>().isOpaque()">]>>;

// Type constraint accepting any LLVM type that can be loaded or stored, i.e. a
// type that has size (not void, function or opaque struct type).
def LLVM_LoadableType : Type<
  And<[LLVM_PrimitiveType.predicate, Neg<LLVM_OpaqueStruct.predicate>]>,
  "LLVM type with size">;

// Type constraint accepting any LLVM aggregate type, i.e. structure or array.
def LLVM_AnyAggregate : Type<
  CPred<"$_self.isa<::mlir::LLVM::LLVMStructType, "
                   "::mlir::LLVM::LLVMArrayType>()">,
  "LLVM aggregate type">;

// Type constraint accepting any LLVM non-aggregate type, i.e. not structure or
// array.
def LLVM_AnyNonAggregate : Type<Neg<LLVM_AnyAggregate.predicate>,
                               "LLVM non-aggregate type">;

// Type constraint accepting any LLVM vector type.
def LLVM_AnyVector : Type<CPred<"$_self.isa<::mlir::LLVM::LLVMVectorType>()">,
                         "LLVM vector type">;

// Type constraint accepting an LLVM vector type with an additional constraint
// on the vector element type.
class LLVM_VectorOf<Type element> : Type<
  And<[LLVM_AnyVector.predicate,
       SubstLeaves<
         "$_self",
         "$_self.cast<::mlir::LLVM::LLVMVectorType>().getElementType()",
         element.predicate>]>,
  "LLVM vector of " # element.description>;

// Type constraint accepting a constrained type, or a vector of such types.
class LLVM_ScalarOrVectorOf<Type element> :
    AnyTypeOf<[element, LLVM_VectorOf<element>]>;

// Base class for LLVM operations. Defines the interface to the llvm::IRBuilder
// used to translate to LLVM IR proper.
class LLVM_OpBase<Dialect dialect, string mnemonic, list<OpTrait> traits = []> :
    Op<dialect, mnemonic, traits> {
  // A pattern for constructing the LLVM IR Instruction (or other Value) that
  // corresponds to this op.  This pattern can use `builder` to refer to an
  // `llvm::IRBuilder<>` instance, $-names of arguments and results and the
  // following special variable names:
  //   - $_resultType - substituted with the LLVM IR type of the result;
  //   - $_numOperands - substituted with the number of operands (including
  //                     the variadic ones);
  //   - $_hasResult - substituted with a check that a variadic-result op does
  //                   have a result (LLVM ops can have 0 or 1 result);
  //   - $_location - mlir::Location object of the instruction.
  // Additionally, `$$` can be used to produce the dollar character.
  string llvmBuilder = "";
}

//===----------------------------------------------------------------------===//
// Base classes for LLVM dialect operations.
//===----------------------------------------------------------------------===//

// Base class for LLVM operations. All operations get an "llvm." prefix in
// their name automatically. LLVM operations have either zero or one result,
// this class is specialized below for both cases and should not be used
// directly.
class LLVM_Op<string mnemonic, list<OpTrait> traits = []> :
    LLVM_OpBase<LLVM_Dialect, mnemonic, traits>;

// Case of the LLVM enum attribute backed by I64Attr with customized string
// representation that corresponds to what is visible in the textual IR form.
// The parameters are as follows:
//   - `cppSym`: name of the C++ enumerant for this case in MLIR API;
//   - `irSym`: keyword used in the custom form of MLIR operation;
//   - `llvmSym`: name of the C++ enumerant for this case in LLVM API.
// For example, `LLVM_EnumAttrCase<"Weak", "weak", "WeakAnyLinkage">` is usable
// as `<MlirEnumName>::Weak` in MLIR API, `WeakAnyLinkage` in LLVM API and
// is printed/parsed as `weak` in MLIR custom textual format.
class LLVM_EnumAttrCase<string cppSym, string irSym, string llvmSym, int val> :
    I64EnumAttrCase<cppSym, val, irSym> {

  // The name of the equivalent enumerant in LLVM.
  string llvmEnumerant = llvmSym;
}

// LLVM enum attribute backed by I64Attr with string representation
// corresponding to what is visible in the textual IR form.
// The parameters are as follows:
//   - `name`: name of the C++ enum class in MLIR API;
//   - `llvmName`: name of the C++ enum in LLVM API;
//   - `description`: textual description for documentation purposes;
//   - `cases`: list of enum cases.
// For example, `LLVM_EnumAttr<Linkage, "::llvm::GlobalValue::LinkageTypes`
// produces `mlir::LLVM::Linkage` enum class in MLIR API that corresponds to (a
// subset of) values in the `llvm::GlobalValue::LinkageTypes` in LLVM API.
class LLVM_EnumAttr<string name, string llvmName, string description,
                    list<LLVM_EnumAttrCase> cases> :
    I64EnumAttr<name, description, cases> {

  // The equivalent enum class name in LLVM.
  string llvmClassName = llvmName;
}

// For every value in the list, substitutes the value in the place of "$0" in
// "pattern" and stores the list of strings as "lst".
class ListIntSubst<string pattern, list<int> values> {
  list<string> lst = !foreach(x, values,
                              !subst("$0", !cast<string>(x), pattern));
}

// Patterns with code obtaining the LLVM IR type of the given operand or result
// of operation. "$0" is expected to be replaced by the position of the operand
// or result in the operation.
def LLVM_IntrPatterns {
  string operand =
    [{convertType(opInst.getOperand($0).getType().cast<LLVM::LLVMType>())}];
  string result =
    [{convertType(opInst.getResult($0).getType().cast<LLVM::LLVMType>())}];
}


// Base class for LLVM intrinsics operation. It is similar to LLVM_Op, but
// provides the "llvmBuilder" field for constructing the intrinsic. The builder
// relies on the contents on "overloadedResults" and "overloadedOperands" lists
// that contain the positions of intrinsic results and operands that are
// overloadable in the LLVM sense, that is their types must be passed in during
// the construction of the intrinsic declaration to differentiate between
// differently-typed versions of the intrinsic. "opName" contains the name of
// the operation to be associated with the intrinsic and "enumName" contains the
// name of the intrinsic as appears in `llvm::Intrinsic` enum; one usually wants
// these to be related.
class LLVM_IntrOpBase<Dialect dialect, string opName, string enumName,
                      list<int> overloadedResults, list<int> overloadedOperands,
                      list<OpTrait> traits, bit hasResult>
    : LLVM_OpBase<dialect, opName, traits>,
      Results<!if(hasResult, (outs LLVM_Type:$res), (outs))> {
  let llvmBuilder = [{
    llvm::Module *module = builder.GetInsertBlock()->getModule();
    llvm::Function *fn = llvm::Intrinsic::getDeclaration(
        module,
        llvm::Intrinsic::}] # enumName # [{,
        { }] # StrJoin<!listconcat(
            ListIntSubst<LLVM_IntrPatterns.result, overloadedResults>.lst,
            ListIntSubst<LLVM_IntrPatterns.operand,
                         overloadedOperands>.lst)>.result # [{
        });
    auto operands = lookupValues(opInst.getOperands());
    }] # !if(hasResult, "$res = ", "") # [{builder.CreateCall(fn, operands);
  }];
}

// Base class for LLVM intrinsic operations, should not be used directly. Places
// the intrinsic into the LLVM dialect and prefixes its name with "intr.".
class LLVM_IntrOp<string mnem, list<int> overloadedResults,
                  list<int> overloadedOperands, list<OpTrait> traits,
                  bit hasResult>
    : LLVM_IntrOpBase<LLVM_Dialect, "intr." # mnem, !subst(".", "_", mnem),
                      overloadedResults, overloadedOperands, traits, hasResult>;

// Base class for LLVM intrinsic operations returning no results. Places the
// intrinsic into the LLVM dialect and prefixes its name with "intr.".
//
// Sample use: derive an entry from this class and populate the fields.
//
//    def LLVM_Name : LLVM_ZeroResultIntrOp<"name", [0], [NoSideEffect]>,
//                    Arguments<(ins LLVM_Type, LLVM_Type)>;
//
// The mnemonic will be prefixed with "llvm.intr.", where the "llvm." part comes
// from the LLVM dialect. The overloadedOperands list contains the indices of
// the operands the type of which will be passed in the LLVM IR intrinsic
// builder. In the example above, the Op has two arguments, but only the first
// one (as indicated by `[0]`) is necessary to resolve the overloaded intrinsic.
// The Op has no results.
class LLVM_ZeroResultIntrOp<string mnem, list<int> overloadedOperands = [],
                            list<OpTrait> traits = []>
    : LLVM_IntrOp<mnem, [], overloadedOperands, traits, 0>;

// Base class for LLVM intrinsic operations returning one result. Places the
// intrinsic into the LLVM dialect and prefixes its name with "intr.". This is
// similar to LLVM_ZeroResultIntrOp but allows one to define Ops returning one
// result, called "res". Additionally, the overloadedResults list should contain
// "0" if the result must be used to resolve overloaded intrinsics, or remain
// empty otherwise.
class LLVM_OneResultIntrOp<string mnem, list<int> overloadedResults = [],
                           list<int> overloadedOperands = [],
                           list<OpTrait> traits = []>
    : LLVM_IntrOp<mnem, overloadedResults, overloadedOperands, traits, 1>;

// LLVM vector reduction over a single vector.
class LLVM_VectorReduction<string mnem>
    : LLVM_OneResultIntrOp<"vector.reduce." # mnem,
                           [], [0], [NoSideEffect]>,
      Arguments<(ins LLVM_Type)>;

// LLVM vector reduction over a single vector, with an initial value,
// and with permission to reassociate the reduction operations.
class LLVM_VectorReductionAcc<string mnem>
    : LLVM_OpBase<LLVM_Dialect, "intr.vector.reduce." # mnem,
                  [NoSideEffect]>,
      Results<(outs LLVM_Type:$res)>,
      Arguments<(ins LLVM_Type, LLVM_Type,
                 DefaultValuedAttr<BoolAttr, "false">:$reassoc)> {
  let llvmBuilder = [{
    llvm::Module *module = builder.GetInsertBlock()->getModule();
    llvm::Function *fn = llvm::Intrinsic::getDeclaration(
        module,
        llvm::Intrinsic::vector_reduce_}] # mnem # [{,
        { }] # StrJoin<ListIntSubst<LLVM_IntrPatterns.operand, [1]>.lst>.result # [{
        });
    auto operands = lookupValues(opInst.getOperands());
    llvm::FastMathFlags origFM = builder.getFastMathFlags();
    llvm::FastMathFlags tempFM = origFM;
    tempFM.setAllowReassoc($reassoc);
    builder.setFastMathFlags(tempFM);  // set fastmath flag
    $res = builder.CreateCall(fn, operands);
    builder.setFastMathFlags(origFM);  // restore fastmath flag
  }];
}

#endif  // LLVMIR_OP_BASE
