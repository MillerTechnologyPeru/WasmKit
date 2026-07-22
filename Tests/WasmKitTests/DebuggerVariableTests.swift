#if WasmDebuggingSupport

    import Testing
    import WAT
    import WasmParser

    @testable import WasmKit

    /// Caller holds a local and calls a single-param callee that sets its own local. Stepping into the
    /// callee must leave both the callee's local and the parent caller frame's local readable with
    /// their correct values, exercising the same `getLocal` path LLDB drives through `qWasmLocal`.
    ///
    /// Reads the callee's declared local and its single param plus the parent-frame local; multi-param
    /// callees are avoided because `getLocal`'s frame-header param addressing predates this change and
    /// mishandles them (not on the Swift async-variable path, which resolves through the async-context
    /// pointer rather than Wasm params).
    /// TODO: fix multi-parameter `getLocal` frame-header addressing (Debugger.getLocal, the `- 4` path).
    private let localsAcrossFramesWAT = """
        (module
          (func $callee (param $a i32) (result i32) (local $x i32)
            (local.set $x (i32.const 99))
            (i32.add (local.get $a) (local.get $x)))
          (func (export "_start") (result i32) (local $c i32)
            (i32.const 7) (local.set $c)
            (call $callee (i32.const 10))))
        """

    @Suite
    struct DebuggerVariableTests {
        @Test
        func localValuesSurviveStepIntoAcrossFrames() throws {
            let store = Store(engine: Engine())
            let module = try parseWasm(bytes: try wat2wasm(localsAcrossFramesWAT))
            var debugger = try Debugger(module: module, store: store, imports: [:])

            let startBase = module.functions[1].code.originalAddress
            // _start body: i32.const 7 (2) + local.set (2) + i32.const 10 (2) + call (2)
            let callSite = startBase + 6
            _ = try debugger.enableBreakpoint(address: callSite)
            try debugger.run()

            #expect(try debugger.getLocal(frameIndex: 0, localIndex: 0) == 7, "caller local $c")

            try debugger.step()

            // After step-in the callee is frame 0 and the caller shifts to frame 1.
            #expect(try debugger.getLocal(frameIndex: 0, localIndex: 0) == 10, "callee param $a")
            #expect(try debugger.getLocal(frameIndex: 1, localIndex: 0) == 7, "caller local $c from parent frame")

            // Step past the local.set so $x is initialised, then confirm the callee local reads back.
            try debugger.step()
            #expect(try debugger.getLocal(frameIndex: 0, localIndex: 1) == 99, "callee local $x after local.set")
        }
    }

#endif
