local Yield = require(1053775069)

---

-- basics
local yield = Yield:new(function()
	Yield:yield(5)
	Yield:yield(7)
	Yield:yield(9)
end)

print(yield:resume())  -- 5
print(yield:resume())  -- 7
print(yield:resume())  -- 9

---

-- parameters
local yield = Yield:new(function(i)
	Yield:yield(i)
	Yield:yield(i + 2)
	Yield:yield(i + 4)
end)

print(yield:resume(10))  -- 10
print(yield:resume())  -- 12
print(yield:resume())  -- 14

---

-- passing things into `:resume`
local yield = Yield:new(function(num1)
	local num2 = Yield:yield(num1)
	local num3 = Yield:yield(num1 + num2)
	return num1 + num2 + num3
end)

-- pass `2` in as `num1`: we get `num1`
print(yield:resume(2))  -- 2
-- pass `3` in as `num2`: we get `num1 + num2`
print(yield:resume(3))  -- 5
-- pass `5` in as `num3`: we get `num1 + num2 + num3`
print(yield:resume(5))  -- 10

---

-- infinite loops and resume
-- this accumulates numbers: every time you give it a number,
--  it adds your number to its value and returns its value
local yield = Yield:new(function(num)
	while true do
		local nextNum = Yield:yield(num)
		num = num + nextNum
	end
end)

print(yield:resume(2))  -- 2
print(yield:resume(3))  -- 5
print(yield:resume(5))  -- 10

---

-- syntax sugar: we can make things look nicer!
local accumulate = Yield(function(num)
	while true do
		num = num + Yield:yield(num)
	end
end)

print(accumulate(2))  -- 2
print(accumulate(3))  -- 5
print(accumulate(5))  -- 10

---

-- yields as loop handlers
local yield = Yield(function()
	for i = 1, 10 do
		Yield:yield(i)
	end
end)

for num in yield do
	print(num)  -- will print 1 through 10
end

---

-- yields as loop handlers 2
local getNums = function(start, count)
	return Yield:new(function()
		for i = start, count do
			Yield:yield(i)
		end
	end)
end

for num in getNums(10, 20) do
	print(num)  -- wil print 1 through 20
end

---
