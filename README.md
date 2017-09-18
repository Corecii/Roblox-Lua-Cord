# Roblox-Lua-Cord
`Cord` is a module that emulates the abilities of coroutines but allows you to `wait` within Cords. It uses Events instead of using coroutines directly, so it works *within* the scheduler.

[Github: Source and Documentation](https://github.com/Corecii/Roblox-Lua-Cord/blob/master/Cord.lua)  
[Roblox Module](https://www.roblox.com/catalog/1053775069/redirect): 1053775069 (`require` compatible)
[DevForum Thread](https://devforum.roblox.com/t/cord-module-coroutine-like-written-for-the-roblox-event-scheduler/52891)

---

Differences from coroutines in Roblox

* If the Cord yields, so does the caller. The caller always waits until the Cord calls `:yield`, returns, or errors.
  * If you want to run a Cord in parallel, then you should call `:resume` in a new coroutine (use `coroutine.wrap`, `spawn`, or `BindableEvent`s). If you do this, you'll have to deal with checking the Cord state to make sure you can `:resume` it. If the Cord is running and you call `:resume` then your code will error.
* If the Cord errors, so does whatever resumed it.
  * You can change this behavior by providing an `ErrorBehavior` when you create a Cord. If you do this, you can use Cord.error to check if an error occured.
    * `Cord:new(function() end, Cord.WARN)` to warn on errors
    * `Cord:new(function() end, Cord.NONE)` to do nothing on errors
