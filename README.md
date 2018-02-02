# Roblox-Lua-Cord
`Cord` is a module that emulates the abilities of coroutines but allows you to `wait` within Cords. It uses Events instead of using coroutines directly, so it works *within* the scheduler.

[Github: Source and Documentation](https://github.com/Corecii/Roblox-Lua-Cord/blob/master/Cord.lua)  
[Roblox Module](https://www.roblox.com/catalog/1381006055/redirect): 1381006055 (`require` compatible)  
[DevForum Thread](https://devforum.roblox.com/t/cord-module-coroutine-like-written-for-the-roblox-event-scheduler/52891)

---

Differences from coroutines in Roblox

* If the Cord yields, so does the caller. The caller always waits until the Cord calls `:yield`, returns, or errors.
* If you want to run a Cord in parallel, you can use the `:parallel` method instead of `:resume`.
  * This will make Cord work like a coroutine
  * You'll have to check `cord.state` or `cord:resumable()` to make sure the cord can be resumed. If you try to resume a running or finished Cord, it will error.
  * You can get the arguments passed to `:yield` or the return values using `cord:returned()` or `cord.outArguments`
* If the Cord errors, so does whatever resumed it.
  * You can change this behavior by providing an `ErrorBehavior` when you create a Cord. If you do this, you can use Cord.error to check if an error occured.
    * `Cord:new(function() end, Cord.WARN)` to warn on errors
    * `Cord:new(function() end, Cord.NONE)` to do nothing on errors
    * `Cord:new(func, function(cord) --[[handle error]] end)` where the result of the error handler is returned to `:resume`
