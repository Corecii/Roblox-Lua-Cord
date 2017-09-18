--[[ API Reference
	
	Class Yield
		METHODS
			static Yield(f: function, errorBehavior: ErrorBehavior [ERROR]) --> yield: Yield
			static :new(f: function, errorBehavior: ErrorBehavior [ERROR]) --> yield: Yield
				Creates a new Yield that will run `f` when resumed
				errorBehavior is optional. If not provided, it defaults to ERROR.
			static :running() --> Yield currentYield
				Returns the Yield that is currently running, or nil if none.
			static :yield(... [a]) --> ... [b]
				Same as non-static `:yield`, but acts on whatever the currently-running Yield is.
				Errors if there is no current Yield.
			:yield(... [a]) --> ... [b]
				Passes ... [a] to whatever `:resume`d this Yield, then waits to be `:resume`d.
				Returns whatever ... [b] in `:resume(... [b])` will be, once resumed.
				Errors if this Yield is not running.
			Yield(... [b]) --> ... [a]
			:resume(... [b]) --> ... [a]
				Passes ... [b] into this Yield as the result of the earlier `:yield` call,
				 then waits for the `:yield`
				Returns whatever the next `:yield(... [a])` will be, once yield is called.
				 If the Yield returns and finished, this returns whatever yield returned
				If this Yield errors, it will return `nil` and the `error` propert will be set.
				Errors if this Yield is running or already finished.
			:getResumeCaller() --> resumeCaller: function
				Returns a function that calls `:resume` on this yield and returns the result
			:getYieldCaller() --> yieldCaller: function
				Returns a function that calls `:yield` on this yield and returns the result
			:finished() --> isFinished: bool
				Returns whether or not the Yield has finished. (`.state < Yield.FINISHED`)
		PROPERTIES
			state: YieldState
				Current state of the Yield. Similar to the results of `coroutine.status`
			errorBehavior: ErrorBehavior
				What to do when there is an error.
			error: Variant
				Only set if the Yield is finished (state = ERROR) and there was an error.
		CONSTANTS
			STOPPED:  YieldState (0)
			RUNNING:  YieldState (1)
			PAUSED:   YieldState (2)
			FINISHED: YieldState (3)
			ERROR:    YieldState (4)
			NONE:  ErrorBehavior (0)
				If used, there are no warnings or errors in the console if an error happens.
			WARN:  ErrorBehavior (1)
				If used, there is a warning in the console if an error happens.
			ERROR: ErrorBehavior (4)
				If used, there is an error in the console if an error happens.
--]]

local function runYield(this)
	this.coroutine = coroutine.running()
	this.globalIndex[this.coroutine] = this
	this.outArguments = {this.func(unpack(this.inArguments))}
end

local function assertMetatable(tbl, meta, err)
	return assert(type(tbl) == "table" and getmetatable(tbl) == meta, err)
end

local function callbackInner(func1, func2, ...)
	return func1(func2(...))
end

local YieldWrap, YieldWrapMeta
YieldWrapMeta = {
	__index = {
		-- YieldState
		STOPPED  = 0,
		RUNNING  = 1,
		PAUSED   = 2,
		FINISHED = 3,
		ERROR    = 4,
		-- ErrorBehavior
		NONE  = 0,
		WARN  = 1,
		ERROR = 4,
		--
		globalIndex = {},
		globalStack = {},
		pushStack = function(this, yieldWrap)
			this.globalStack[#this.globalStack + 1] = yieldWrap
		end,
		popStack = function(this)
			local yieldWrap = this.globalStack[#this.globalStack]
			this.globalStack[#this.globalStack] = nil
			return yieldWrap
		end,
		running = function(this)
			assertMetatable(this, YieldWrapMeta, "Expected ':' not '.' calling member function running")
			local current = this.globalIndex[coroutine.running()]
			if current then
				-- easy! current Yield is whichever the current coroutine is!
				return current
			else
				-- looks like it shifted to another coroutine, but hasn't waited at all yet
				-- in that case, we need to find which coroutine is active, but not suspended or dead
				-- we want to find the most recent one like this: it's possible for a Yield to
				--  resume another Yield, so we need to get the most recent one resumed!
				local globalStack = this.globalStack
				for i = #globalStack, 1, -1 do
					local v = globalStack[i]
					if coroutine.status(v.coroutine) == "normal" then
						return v
					end
				end
			end
		end,
		new = function(this, ...)
			assert(this == YieldWrap, "Expected ':' not '.' calling constructor Yield")
			local newYield = setmetatable({}, YieldWrapMeta)
			newYield:construct(...)
			return newYield
		end,
		construct = function(this, func, errorBehavior)
			assert(type(func) == "function" or type(func) == "table", "`f` should be a function or table")
			this.func = func
			this.errorBehavior = errorBehavior or this.ERROR
			assert(type(this.errorBehavior) == "number", "errorBehavior should be an ErrorBehavior or nil.")
			this.inEvent = Instance.new("BindableEvent")
			this.outEvent = Instance.new("BindableEvent")
			this.inArguments = {}
			this.outArguments = {}
			this.state = this.STOPPED
			local conn
			conn = this.inEvent.Event:connect(function()
				conn:disconnect()
				this.state = this.RUNNING
				this:pushStack(this)
				local success, err = pcall(runYield, this)
				this:popStack()
				this.globalIndex[this.coroutine] = nil
				if success then
					this.state = this.FINISHED
				else
					this.outArguments = {}
					this.state = this.ERROR
					this.error = err
				end
				this.outEvent:Fire()
			end)
		end,
		yield = function(this, ...)
			assertMetatable(this, YieldWrapMeta, "Expected ':' not '.' calling member function yield")
			if this == YieldWrap then
				return assert(this:running(), "No Yield is running."):yield(...)
			end
			if this.state >= this.FINISHED then
				error("Cannot yield when already finished")
			elseif this.state == this.STOPPED then
				error("Cannot yield before started")
			elseif this.state == this.PAUSED then
				error("Cannot yield while paused")
			end
			this.outArguments = {...}
			local inArgs
			local conn
			conn = this.inEvent.Event:connect(function()
				conn:disconnect()
				inArgs = this.inArguments
			end)
			this.state = this.PAUSED
			this:popStack()
			this.outEvent:Fire()
			if not inArgs then
				this.inEvent.Event:wait()
				inArgs = this.inArguments
			end
			this:pushStack(this)
			this.state = this.RUNNING
			return unpack(inArgs)
		end,
		resume = function(this, ...)
			assertMetatable(this, YieldWrapMeta, "Expected ':' not '.' calling member function resume")
			if this.state >= this.FINISHED then
				error("Cannot resume when already finished")
			elseif this.state == this.RUNNING then
				error("Cannot resume while running")
			end
			this.inArguments = {...}
			local outArgs
			local conn
			conn = this.outEvent.Event:connect(function()
				conn:disconnect()
				outArgs = this.outArguments
			end)
			this.inEvent:Fire()
			if not outArgs then
				this.outEvent.Event:wait()
				outArgs = this.outArguments
			end
			if this.error and this.errorBehavior ~= this.NONE then
				if this.errorBehavior == this.WARN then
					warn("Error in Yield: "..tostring(this.error))
				elseif this.errorBehavior == this.ERROR then
					error("Error in Yield: "..tostring(this.error))
				end
			end
			return unpack(outArgs)
		end,
		getYieldCaller = function(this)
			assertMetatable(this, YieldWrapMeta, "Expected ':' not '.' calling member function getYieldCaller")
			if not this.yieldCaller then
				this.yieldCaller = function(...)
					return this:yield(...)
				end
			end
			return this.yieldCaller
		end,
		getResumeCaller = function(this)
			assertMetatable(this, YieldWrapMeta, "Expected ':' not '.' calling member function getResumeCaller")
			if not this.resumeCaller then
				this.resumeCaller = function(...)
					return this:resume(...)
				end
			end
			return this.resumeCaller
		end,
		finished = function(this)
			assertMetatable(this, YieldWrapMeta, "Expected ':' not '.' calling member function finished")
			return this.state < this.FINISHED
		end
	},
	__call = function(this, ...)
		if this == YieldWrap then
			return this:new(...)
		else
			return this:resume(...)
		end
	end
}

YieldWrap = setmetatable({}, YieldWrapMeta)

return YieldWrap
