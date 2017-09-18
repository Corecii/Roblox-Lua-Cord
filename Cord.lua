--[[ API Reference
	
	Class Cord
		METHODS
			static Cord(f: function, errorBehavior: ErrorBehavior [ERROR] | function) --> yield: Cord
			static :new(f: function, errorBehavior: ErrorBehavior [ERROR] | function) --> yield: Yield
				Creates a new Cord that will run `f` when resumed
				errorBehavior is optional. If not provided, it defaults to ERROR. Check :resume for docs.
			static :running(findExtended: bool [false]) --> currentCord: Cord
				Returns the Cord that is currently running, or nil if none.
				if findExtended is true, this also looks for a Cord that is technically
				 executing, but where any yields in the current context will split the context
				 off into a new coroutine where the Cord is not active.
			static :yield(... [a]) --> ... [b]
				Same as non-static `:yield`, but acts on whatever the currently-running Cord is.
				Generally, you should be using this instead of cord-specific yields!
				Using cord-specific yields is a pathway to errors and bugs that lock up your script!
				Errors if there is no current Cord, or if the current context is not within the current Cord.
			:yield(... [a]) --> ... [b]
				Passes ... [a] to whatever `:resume`d this Cord, then waits to be `:resume`d.
				Returns whatever ... [b] in `:resume(... [b])` will be, once resumed.
				Errors if this Cord is not running.
			Cord(... [b]) --> ... [a]
			:resume(... [b]) --> ... [a]
				Passes ... [b] into this Cord as the result of the earlier `:yield` call,
				 then waits for the `:yield`
				Returns whatever the next `:yield(... [a])` will be, once yield is called.
				 If the Cord returns and finished, this returns whatever yield returned
				If this Cord errors...
				* if errorBehavior is ERROR, then resume will error with the error.
				* if errorBehavior is WARN, then resume will warn with the error, then...
				* if errorBehavior is WARN or NONE, it will return `nil` and the `error` property will be set.
				* if errorBehavior is a function, then `errorBehavior(error: string, cord: Cord)` is called,
				   and the result is returned.
				Errors if this Cord is running or already finished.
			:getResumeCaller() --> resumeCaller: function
				Returns a function that calls `:resume` on this yield and returns the result
			:getYieldCaller() --> yieldCaller: function
				Returns a function that calls `:yield` on this yield and returns the result
			:finished() --> isFinished: bool
				Returns whether or not the Cord has finished. (`.state < Cord.FINISHED`)
		PROPERTIES
			state: CordState
				Current state of the Cord. Similar to the results of `coroutine.status`
			errorBehavior: ErrorBehavior
				What to do when there is an error.
			error: Variant
				Only set if the Cord is finished (state = ERROR) and there was an error.
		CONSTANTS
			STOPPED:  CordState (0)
			RUNNING:  CordState (1)
			PAUSED:   CordState (2)
			FINISHED: CordState (3)
			ERROR:    CordState (4)
			NONE:  ErrorBehavior (0)
				If used, there are no warnings or errors in the console if an error happens.
			WARN:  ErrorBehavior (1)
				If used, there is a warning in the console if an error happens.
			ERROR: ErrorBehavior (4)
				If used, there is an error in the console if an error happens.
--]]

local function runCord(this)
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

local CordWrap, CordWrapMeta
CordWrapMeta = {
	__index = {
		-- CordState
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
		running = function(this, findExtended)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function running")
			local current = this.globalIndex[coroutine.running()]
			if current then
				-- easy! current Cord is whichever the current coroutine is!
				return current
			elseif findExtended then
				-- looks like it shifted to another coroutine, but hasn't waited at all yet
				-- in that case, we need to find which coroutine is active, but not suspended or dead
				-- we want to find the most recent one like this: it's possible for a Cord to
				--  resume another Cord, so we need to get the most recent one resumed!
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
			assert(this == CordWrap, "Expected ':' not '.' calling constructor Cord")
			local newCord = setmetatable({}, CordWrapMeta)
			newCord:construct(...)
			return newCord
		end,
		construct = function(this, func, errorBehavior)
			assert(type(func) == "function" or type(func) == "table", "`f` should be a function or table")
			this.func = func
			this.errorBehavior = errorBehavior or this.ERROR
			assert(type(this.errorBehavior) == "number" or type(this.errorBehavior) == "function", "errorBehavior should be an ErrorBehavior, a function, or nil.")
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
				local success, err = pcall(runCord, this)
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
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function yield")
			if this == CordWrap then
				return assert(this:running(true), "No Cord is running."):yield(...)
			end
			if this.state >= this.FINISHED then
				error("Cannot yield when already finished")
			elseif this.state == this.STOPPED then
				error("Cannot yield before started")
			elseif this.state == this.PAUSED then
				error("Cannot yield while paused")
			end
			if coroutine.status(this.coroutine) ~= "running" then
				error(":yield called from outside the Cord")
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
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function resume")
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
					warn("Error in Cord: "..tostring(this.error))
				elseif this.errorBehavior == this.ERROR then
					error("Error in Cord: "..tostring(this.error))
				elseif type(this.errorBehavior) == "function" then
					outArgs = {this.errorBehavior(this.error, this)}
				end
			end
			return unpack(outArgs)
		end,
		getYieldCaller = function(this)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function getYieldCaller")
			if not this.yieldCaller then
				this.yieldCaller = function(...)
					return this:yield(...)
				end
			end
			return this.yieldCaller
		end,
		getResumeCaller = function(this)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function getResumeCaller")
			if not this.resumeCaller then
				this.resumeCaller = function(...)
					return this:resume(...)
				end
			end
			return this.resumeCaller
		end,
		finished = function(this)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function finished")
			return this.state < this.FINISHED
		end
	},
	__call = function(this, ...)
		if this == CordWrap then
			return this:new(...)
		else
			return this:resume(...)
		end
	end
}

CordWrap = setmetatable({}, CordWrapMeta)

return CordWrap
