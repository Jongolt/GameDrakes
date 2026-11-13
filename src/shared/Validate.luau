--!strict
-- An own validator of the remote call arguments (10 §4, craft/01 §3): the type, the range, the string length, membership in a list.
-- The schema is an array of positional argument descriptions. No third-party libraries. Pure logic.

local Validate = {}

export type Spec = {
	name: string,
	type: string, -- "string" | "integer" | "number" | "boolean" | "enum" | "table"
	optional: boolean?,
	min: number?, -- for numbers
	max: number?, -- for numbers and string lengths
	values: { string }?, -- for enums
}

-- Returns ok and the reason ("bad_request:<name>")
function Validate.args(args: { any }, schema: { Spec }): (boolean, string?)
	for i, spec in schema do
		local v = args[i]
		if v == nil then
			if spec.optional then
				continue
			end
			return false, "bad_request:" .. spec.name
		end
		local t = spec.type
		if t == "string" then
			if type(v) ~= "string" or (spec.max and #v > spec.max) or #v == 0 then
				return false, "bad_request:" .. spec.name
			end
		elseif t == "integer" then
			if type(v) ~= "number" or v ~= v or v % 1 ~= 0 or (spec.min and v < spec.min) or (spec.max and v > spec.max) then
				return false, "bad_request:" .. spec.name
			end
		elseif t == "number" then
			if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge or (spec.min and v < spec.min) or (spec.max and v > spec.max) then
				return false, "bad_request:" .. spec.name
			end
		elseif t == "boolean" then
			if type(v) ~= "boolean" then
				return false, "bad_request:" .. spec.name
			end
		elseif t == "enum" then
			if type(v) ~= "string" or not spec.values or not table.find(spec.values, v) then
				return false, "bad_request:" .. spec.name
			end
		elseif t == "table" then
			if type(v) ~= "table" then
				return false, "bad_request:" .. spec.name
			end
		else
			return false, "bad_schema:" .. spec.name
		end
	end
	if #args > #schema then
		return false, "bad_request:extra"
	end
	return true, nil
end

return Validate
