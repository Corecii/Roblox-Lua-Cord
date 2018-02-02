--[[ API Reference
	
	Class Cord
		METHODS
			static Cord(f: function, errorBehavior: ErrorBehavior [ERROR] | function) --> cord: Cord
			static :new(f: function, errorBehavior: ErrorBehavior [ERROR] | function) --> cord: Cord
				Creates a new Cord that will run `f` when resumed
				errorBehavior is optional. If not provided, it defaults to ERROR. Check :resume for docs.
			static :running() --> currentCord: Cord
				Returns the Cord that is currently running, or nil if none.
				Will return nil if the "currently running" Cord is actually the "parent" coroutine
			static :yield(... [a]) --> ... [b]
				Same as non-static `:yield`, but acts on whatever the currently-running Cord is.
				This is preferred to using Cord-instance `:yield`
				Errors if there is no current Cord, or if the current context is not within the current Cord.
			:yield(... [a]) --> ... [b]
				Passes ... [a] to the `:resume` that resumed this Cord, then waits to be resumed.
				Waits for then returns ... [b] in `:resume(... [b])` 
				Errors if this Cord is not running.
			Cord(... [b]) --> ... [a]
			:resume(... [b]) --> ... [a]
				If the Cord has not been ran, this calls the Cord function with ... [b], and
				 returns the result of the first `:yield(... [a])` as ... [a]
				Passes ... [b] into this Cord as the result of the earlier `:yield` call,
				 then waits for the `:yield(... [a])` and returns the result as ... [a]
				Waits for then returns ... [a] from `:yield(... [a])`
				 If the Cord function finishes or returns, this returns whatever the Cord function returned.
				 If this Cord errors...
				 * if errorBehavior is ERROR, then resume will error with the error.
				 * if errorBehavior is WARN, then resume will warn with the error, then...
				 * if errorBehavior is WARN or NONE, it will return `nil` and the `error` property will be set.
				 * if errorBehavior is a function or table, then `errorBehavior(cord: Cord)` is called,
				   and the result is returned. This accepts tables with a __call metamethod.
				Errors if this Cord is running or already finished.
			:parallel(...) --> void
				Same as resume, but it does not wait for the Cord to return, so execution runs in "parallel".
				If `:resume` or `:parallel` is called before the Cord yields, then they will error. You will
				 have to check `thisCord.state` before calling either, or otherwise guarantee that the Cord has yielded.
				You can get the return/yield arguments from this Cord using `thisCord.outArguments` table.
				 You can use `thisCord:returned()` to get this like a normal return.
			:getResumeCaller() --> resumeCaller: function
				Returns a function that calls `:resume` on this Cord and returns the result
			:getYieldCaller() --> yieldCaller: function
				Returns a function that calls `:yield` on this Cord and returns the result
			:returned() --> ...
				Returns what this Cord last returned, either as arguments to `:yield` or as a final return
			:finished() --> isFinished: bool
				Returns true if this Cord has finished or errored
			:resumable() --> isResumable: bool
				Returns true if this Cord can be resumed


		PROPERTIES
			state: CordState
				Current state of the Cord. Similar to the results of `coroutine.status`
			errorBehavior: ErrorBehavior
				What to do when there is an error.
			error: Variant
				Only set if the Cord is finished (state = ERROR) and there was an error.
		CONSTANTS
			CordState
				STOPPED  = "STOPPED"
				RUNNING  = "RUNNING"
				PAUSED   = "PAUSED"
				FINISHED = "FINISHED"
				ERROR    = "ERROR"
			ErrorBehavior
				NONE  = "NONE"
					If used, there are no warnings or errors in the console if an error happens.
					The state will be "ERROR", and the error will be in the `error` property.
				WARN  = "WARN"
					If used, there is a warning in the console if an error happens.
					The state will be "ERROR", and the error will be in the `error` property.
				ERROR = "ERROR"
					If used, there is an error in the console if an error happens.
--]]

local globalIndex = {}

local function runCord(this)
	this.coroutine = coroutine.running()
	globalIndex[this.coroutine] = this
	this.outArguments = {this.func(unpack(this.inArguments))}
end

local function assertMetatable(tbl, meta, err)
	return assert(type(tbl) == "table" and getmetatable(tbl) == meta, err)
end

local ErrorBehavior = {
	NONE     = "NONE",
	WARN     = "WARN",
	ERROR    = "ERROR",
}

local CordState = {
	STOPPED  = "STOPPED",
	RUNNING  = "RUNNING",
	PAUSED   = "PAUSED",
	FINISHED = "FINISHED",
	ERROR    = "ERROR",
}

local CordWrap, CordWrapMeta
CordWrapMeta = {
	__index = {
		ErrorBehavior = ErrorBehavior,
		CordState = CordState,
		globalIndex = globalIndex,
		running = function(this)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function running")
			return globalIndex[coroutine.running()]
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
			errorBehavior = errorBehavior or "ERROR"
			this.errorBehavior = errorBehavior
			assert(
				(type(errorBehavior) == "string" and ErrorBehavior[errorBehavior])
				or type(errorBehavior) == "function"
				or type(errorBehavior) == "table",
				"errorBehavior should be an ErrorBehavior string, a function, a table, or nil.")
			this.inEvent = Instance.new("BindableEvent")
			this.outEvent = Instance.new("BindableEvent")
			this.inArguments = {}
			this.outArguments = {}
			this.state = "STOPPED"
			local conn
			conn = this.inEvent.Event:connect(function()
				conn:disconnect()
				this.state = "RUNNING"
				local success, err = pcall(runCord, this)
				globalIndex[this.coroutine] = nil
				if success then
					this.state = "FINISHED"
				else
					this.outArguments = {}
					this.state = "ERROR"
					this.error = err
				end
				this.outEvent:Fire()
			end)
		end,
		yield = function(this, ...)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function yield")
			if this == CordWrap then
				return assert(this:running(), "No Cord is running."):yield(...)
			end
			if this.state == "FINISHED" or this.state == "ERROR" then
				error("Cannot yield when already finished")
			elseif this.state == "STOPPED" then
				error("Cannot yield before started")
			elseif this.state == "PAUSED" then
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
			this.state = "PAUSED"
			this.outEvent:Fire()
			if not inArgs then
				this.inEvent.Event:wait()
				inArgs = this.inArguments
			end
			this.state = "RUNNING"
			return unpack(inArgs)
		end,
		resume = function(this, ...)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function resume")
			if this.state == "FINISHED" or this.state == "ERROR" then
				error("Cannot resume when already finished")
			elseif this.state == "RUNNING" then
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
			if this.error and this.errorBehavior ~= "NONE" then
				local errorBehavior = this.errorBehavior
				if errorBehavior == "WARN" then
					warn("Error in Cord: "..tostring(this.error))
				elseif errorBehavior == "ERROR" then
					error("Error in Cord: "..tostring(this.error))
				elseif type(errorBehavior) == "function" or type(errorBehavior) == "table" then
					outArgs = {errorBehavior(this)}
				end
			end
			return unpack(outArgs)
		end,
		parallel = function(this, ...)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function parellel")
			if this.state == "FINISHED" or this.state == "ERROR" then
				error("Cannot resume when already finished")
			elseif this.state == this.RUNNING then
				error("Cannot resume while running")
			end
			this.inArguments = {...}
			local outArgs
			local conn
			conn = this.outEvent.Event:connect(function()
				conn:disconnect()
				if this.error and this.errorBehavior ~= "NONE" then
					local errorBehavior = this.errorBehavior
					if errorBehavior == "WARN" then
						warn("Error in Cord: "..tostring(this.error))
					elseif errorBehavior == "ERROR" then
						error("Error in Cord: "..tostring(this.error))
					elseif type(errorBehavior) == "function" or type(errorBehavior) == "table" then
						outArgs = {errorBehavior(this)}
					end
				end
			end)
			this.inEvent:Fire()
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
		returned = function(this)
			return unpack(this.outArguments)
		end,
		finished = function(this)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function finished")
			return this.state == "FINISHED" or this.state == "ERROR"
		end,
		resumable = function(this)
			assertMetatable(this, CordWrapMeta, "Expected ':' not '.' calling member function finished")
			return this.state == "STOPPED" or this.state == "PAUSED"
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
