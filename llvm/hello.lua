#!/usr/bin/env luajit

local ffi = require('ffi')
local llvm = require('llvm')

local i8 = llvm.LLVMIntType(8)
local i8p = llvm.LLVMPointerType(i8, 0)
local i8pp = llvm.LLVMPointerType(i8p, 0)
local i32 = llvm.LLVMIntType(32)

local const_i32_0 = llvm.LLVMConstInt(i32, 0, false)

local function declare_func(mod, name, ret_type, arg_types, opts)
   opts = opts or {}
   local argsT = ffi.new("LLVMTypeRef[?]", #arg_types, arg_types)
   local funcT = llvm.LLVMFunctionType(ret_type, argsT, #arg_types, opts.vararg or false)
   local func = llvm.LLVMAddFunction(mod, name, funcT)
   llvm.LLVMSetLinkage(func, opts.linkage or llvm.LLVMExternalLinkage)
   llvm.LLVMSetFunctionCallConv(func, opts.cc or llvm.LLVMCCallConv)
   if opts.params then
      for i,name in ipairs(opts.params) do
         llvm.LLVMSetValueName(llvm.LLVMGetParam(func, i-1), name)
      end
   end
   return func
end

local function declare_printf(mod)
   declare_func(mod, "printf", i32, {i8p}, {vararg=true, params={"format"}})
end

local function define_main(mod)
   local func = declare_func(mod, "main", i32, {i32, i8pp}, {params={"argc", "argv"}})
   local block = llvm.LLVMAppendBasicBlock(func, "entry")
   local builder = llvm.LLVMCreateBuilder()
   llvm.LLVMPositionBuilder(builder, block, nil)
   local hello = "Hello, world!\n"
   local const_hello = llvm.LLVMConstString(hello, #hello, false)
   local var_hello = llvm.LLVMAddGlobal(mod,
                                        llvm.LLVMTypeOf(const_hello),
                                        "hello")
   llvm.LLVMSetInitializer(var_hello, const_hello)
   llvm.LLVMSetGlobalConstant(var_hello, true)
   llvm.LLVMSetLinkage(var_hello, llvm.LLVMPrivateLinkage)
   local printf_args = ffi.new("LLVMValueRef[1]")
   local gep_indices = ffi.new("LLVMValueRef[2]", {const_i32_0, const_i32_0})
   printf_args[0] = llvm.LLVMConstGEP(var_hello, gep_indices, 2)
   local printf = llvm.LLVMGetNamedFunction(mod, "printf")
   llvm.LLVMBuildCall(builder, printf, printf_args, 1, "")
   llvm.LLVMBuildRet(builder, const_i32_0)
   llvm.LLVMDisposeBuilder(builder)
end

local function make_llvm_module()
   local mod = llvm.LLVMModuleCreateWithName("hello")
   declare_printf(mod)
   define_main(mod)
   return mod
end

local function verify_module(mod)
   local outmsg = ffi.new("char*[1]")
   llvm.LLVMVerifyModule(mod, llvm.LLVMAbortProcessAction, outmsg)
   if outmsg ~= nil then
      llvm.LLVMDisposeMessage(outmsg[0])
   end
end

local function run_passes(mod)
   local pm = llvm.LLVMCreatePassManager()
   llvm.LLVMRunPassManager(pm, mod)
   -- unfortunately, there is no such function:
   -- llvm.LLVMAddPrintModulePass(pm)
   llvm.LLVMDisposePassManager(pm)
end

local function create_execution_engine(mod)
   local jit_opts = ffi.new("struct LLVMMCJITCompilerOptions")
   llvm.LLVMInitializeMCJITCompilerOptions(jit_opts, ffi.sizeof(jit_opts))
   local ee = ffi.new("LLVMExecutionEngineRef[1]")
   local outmsg = ffi.new("char*[1]")
   if not llvm.LLVMCreateMCJITCompilerForModule(ee,
                                                mod,
                                                jit_opts,
                                                ffi.sizeof(jit_opts),
                                                outmsg) then
      error("Cannot create execution engine: "+ffi.string(outmsg[0]))
   end
   ee = ee[0]
   if ee == nil then
      assert(outmsg[0] ~= nil)
      error(ffi.string(outmsg[0]))
   end
   return ee
end

local function main()
   local target = llvm.LLVMGetDefaultTargetTriple()
   if target ~= nil then
      print("default target: "..ffi.string(target))
      llvm.LLVMDisposeMessage(target)
   end

   local mod = make_llvm_module()
   verify_module(mod)
   run_passes(mod)

   -- as we could't create a PrintModulePass via the C API,
   -- let's dump the module using a different API call
   llvm.LLVMDumpModule(mod)

   local ee = create_execution_engine(mod)
   local main = llvm.LLVMGetNamedFunction(mod, "main")
   local result = llvm.LLVMRunFunction(ee, main, 0, nil)
   llvm.LLVMDisposeExecutionEngine(ee)

   -- ee took ownership of the module
   -- disposing it would cause a double-free
   --llvm.LLVMDisposeModule(mod)

   return result
end

main()
