//===--- Genode.h - Genode ToolChain Implementations ------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_GENODE_H
#define LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_GENODE_H

#include "Gnu.h"
#include "clang/Driver/Tool.h"
#include "clang/Driver/ToolChain.h"

namespace clang {
namespace driver {
namespace tools {
namespace genode {
class LLVM_LIBRARY_VISIBILITY Linker final : public Tool {
public:
  Linker(const ToolChain &TC) : Tool("genode::Linker", "linker", TC) {}

  bool hasIntegratedCPP() const final { return false; }
  bool isLinkJob() const final { return true; }

  void ConstructJob(Compilation &C, const JobAction &JA,
                    const InputInfo &Output, const InputInfoList &Inputs,
                    const llvm::opt::ArgList &TCArgs,
                    const char *LinkingOutput) const final;
};
} // end namespace genode
} // end namespace tools

namespace toolchains {

class LLVM_LIBRARY_VISIBILITY Genode final : public Generic_ELF {
public:
  Genode(const Driver &D, const llvm::Triple &Triple,
         const llvm::opt::ArgList &Args);

  bool IsMathErrnoDefault() const final { return false; }
  bool HasNativeLLVMSupport() const final { return false; }
  bool isPICDefault() const final { return true; }
  bool isPIEDefault() const final { return false; }
  bool isPICDefaultForced() const final { return false; }
  bool IsIntegratedAssemblerDefault() const final { return true; }

  void
  AddClangSystemIncludeArgs(const llvm::opt::ArgList &DriverArgs,
                            llvm::opt::ArgStringList &CC1Args) const final;
  void
  addLibStdCxxIncludePaths(const llvm::opt::ArgList &DriverArgs,
                           llvm::opt::ArgStringList &CC1Args) const final;

  bool IsUnwindTablesDefault(const llvm::opt::ArgList &Args) const final {
    return true;
  }

  void addExtraOpts(llvm::opt::ArgStringList &CmdArgs) const final;

  const char *getDefaultLinker() const final {
    return "ld.lld";
  }

  RuntimeLibType GetDefaultRuntimeLibType() const final;
  CXXStdlibType GetDefaultCXXStdlibType() const final {
    return ToolChain::CST_Libstdcxx;
  }

  std::vector<std::string> ExtraOpts;

protected:
  Tool *buildLinker() const override;
};

} // end namespace toolchains
} // end namespace driver
} // end namespace clang

#endif // LLVM_CLANG_LIB_DRIVER_TOOLCHAINS_GENODE_H
