local Cord = require(1053775069)

---

-- basics
local cord = Cord:new(function()
	Cord:yield(5)
	Cord:yield(7)
	Cord:yield(9)
end)

print(cord:resume())  -- 5
print(cord:resume())  -- 7
print(cord:resume())  -- 9

---

-- parameters
local cord = Cord:new(function(i)
	Cord:yield(i)
	Cord:yield(i + 2)
	Cord:yield(i + 4)
end)

print(cord:resume(10))  -- 10
print(cord:resume())  -- 12
print(cord:resume())  -- 14

---

-- passing things into `:resume`
local cord = Cord:new(function(num1)
	local num2 = Cord:yield(num1)
	local num3 = Cord:yield(num1 + num2)
	return num1 + num2 + num3
end)

-- pass `2` in as `num1`: we get `num1`
print(cord:resume(2))  -- 2
-- pass `3` in as `num2`: we get `num1 + num2`
print(cord:resume(3))  -- 5
-- pass `5` in as `num3`: we get `num1 + num2 + num3`
print(cord:resume(5))  -- 10

---

-- infinite loops and resume
-- this accumulates numbers: every time you give it a number,
--  it adds your number to its value and returns its value
local cord = Cord:new(function(num)
	while true do
		local nextNum = Cord:yield(num)
		num = num + nextNum
	end
end)

print(cord:resume(2))  -- 2
print(cord:resume(3))  -- 5
print(cord:resume(5))  -- 10

---

-- syntax sugar: we can make things look nicer!
local accumulate = Cord(function(num)
	while true do
		num = num + Cord:yield(num)
	end
end)

print(accumulate(2))  -- 2
print(accumulate(3))  -- 5
print(accumulate(5))  -- 10

---

-- cords as loop handlers
local cord = Cord(function()
	for i = 1, 10 do
		Cord:yield(i)
	end
end)

for num in cord do
	print(num)  -- will print 1 through 10
end

---

-- cords as loop handlers 2
local getNums = function(start, count)
	return Cord:new(function()
		for i = start, count do
			Cord:yield(i)
		end
	end)
end

for num in getNums(10, 20) do
	print(num)  -- wil print 1 through 20
end


---
