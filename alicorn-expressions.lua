-- get new version of let and do working with terms

local metalanguage = require "./metalanguage"
-- local conexpr = require './contextual-exprs'
local types = require "./typesystem"

local terms = require "./terms"
local expression_goal = terms.expression_goal
local runtime_context = terms.runtime_context
local typechecking_context = terms.typechecking_context
local checkable_term = terms.checkable_term
local inferrable_term = terms.inferrable_term
local typed_term = terms.typed_term
local visibility = terms.visibility
local purity = terms.purity
local result_info = terms.result_info
local value = terms.value
local prim_syntax_type = terms.prim_syntax_type
local prim_environment_type = terms.prim_environment_type
local prim_inferrable_term_type = terms.prim_inferrable_term_type

local gen = require "./terms-generators"
local array = gen.declare_array
local checkable_array = array(checkable_term)
local inferrable_array = array(inferrable_term)
local typed_array = array(typed_term)
local value_array = array(value)
local usage_array = array(gen.builtin_number)
local name_array = array(gen.builtin_string)

local param_info_explicit = value.param_info(value.visibility(visibility.explicit))
local param_info_implicit = value.param_info(value.visibility(visibility.implicit))
local result_info_pure = value.result_info(result_info(purity.pure))
local result_info_effectful = value.result_info(result_info(purity.effectful))
local function tup_val(...)
	return value.tuple_value(value_array(...))
end
local function cons(...)
	return value.enum_value("cons", tup_val(...))
end
local empty = value.enum_value("empty", tup_val())

local evaluator = require "./evaluator"
local const_combinator = evaluator.const_combinator
local infer = evaluator.infer

local p = require "pretty-print".prettyPrint
local U = require "./utils"

local semantic_error_mt = {
	__tostring = function(self)
		local message = self.text
		if self.anchors then
			message = message .. " at anchors"
			for _, anchor in ipairs(self.anchors) do
				message = " " .. message .. " " .. tostring(anchor)
			end
		end
		if self.terms then
			message = message .. " with terms\n"
			for k, term in pairs(self.terms) do
				local s = nil
				if term.pretty_print and self.env then
					s = term:pretty_print(self.env.typechecking_context)
				else
					s = tostring(term)
				end
				message = message .. k .. " = " .. s .. "\n"
			end
		end
		if self.env then
			message = message .. " in env\n"
			message = message .. self.env.typechecking_context:format_names() .. "\n"
		end
		if self.cause then
			message = message .. " because:\n" .. tostring(self.cause)
		end
		return message
	end,
}

local semantic_error = {
	---@param cause any
	function_args_mismatch = function(cause)
		return {
			text = "function args mismatch",
			cause = cause,
		}
	end,
	---@param t any
	non_operable_combiner = function(t)
		return {
			text = "value in combiner slot that can't operate of type " .. types.type_name(t),
		}
	end,
	---@param cause any
	---@param anchors Anchor[]
	operative_apply_failed = function(cause, anchors)
		return {
			text = "operative apply failed",
			cause = cause,
			anchors = anchors,
		}
	end,
	---@param cause any
	---@param anchors Anchor[]
	---@param terms any
	---@param env any
	---@return table
	prim_function_argument_collect_failed = function(cause, anchors, terms, env)
		return {
			text = "prim_function_argument_collect_failed",
			cause = cause,
			anchors = anchors,
			terms = terms,
			env = env,
		}
	end,
}

for k, v in pairs(semantic_error) do
	semantic_error[k] = function(...)
		return setmetatable(v(...), semantic_error_mt)
	end
end

local expression
local collect_tuple
local collect_prim_tuple

---@class ExpressionArgs
---@field goal expression_goal
---@field env Environment
local ExpressionArgs = {}

---Unpack ExpressionArgs into component parts
---@return expression_goal
---@return Environment
function ExpressionArgs:unwrap()
	return self.goal, self.env
end

---@param goal expression_goal
---@param env Environment
---@return ExpressionArgs
function ExpressionArgs.new(goal, env)
	if not goal then
		error("missing or incorrect goal passed to expression_args")
	end
	if not env or not env.get then
		error("missing or incorrect env passed to expression_args")
	end
	return setmetatable({
		goal = goal,
		env = env,
	}, { __index = ExpressionArgs })
end

-- work around lua lsp not warning about invalid enum accesses
---@class OperatorTypeContainer
local OperatorType = --[[@enum OperatorType]]
	{
		Prefix = "Prefix",
		Infix = "Infix",
	}

---@class (exact) PrefixData

---@type {[string]: PrefixData}
local prefix_data = {
	["-"] = {},
	["@"] = {},
}

---@class AssociativityContainer
local Associativity = --[[@enum Associativity]]
	{
		r = "r",
		l = "l",
	}

---@class (exact) InfixData
---@field precedence integer
---@field associativity Associativity

---@type {[string]: InfixData}
local infix_data = {
	["="] = { precedence = 2, associativity = "r" },
	["|"] = { precedence = 3, associativity = "l" },
	["&"] = { precedence = 3, associativity = "l" },
	["!"] = { precedence = 3, associativity = "l" },
	["<"] = { precedence = 4, associativity = "l" },
	[">"] = { precedence = 4, associativity = "l" },
	["+"] = { precedence = 5, associativity = "l" },
	["-"] = { precedence = 5, associativity = "l" },
	["*"] = { precedence = 6, associativity = "l" },
	["/"] = { precedence = 6, associativity = "l" },
	["%"] = { precedence = 6, associativity = "l" },
	["^"] = { precedence = 7, associativity = "r" },
	[":"] = { precedence = 8, associativity = "l" },
	-- # is the comment character and is forbidden here
}

---@param symbol string
---@return boolean
---@return string
local function shunting_yard_prefix_handler(_, symbol)
	if not prefix_data[symbol:sub(1, 1)] then
		return false,
			"symbol was provided in a prefix operator place, but the symbol isn't a valid prefix operator: " .. symbol
	end
	return true, symbol
end

---@param symbol string
---@param a ConstructedSyntax
---@param b ConstructedSyntax
---@return boolean
---@return boolean|string
---@return string?
---@return ConstructedSyntax?
---@return ConstructedSyntax?
local function shunting_yard_infix_handler(_, symbol, a, b)
	if not infix_data[symbol:sub(1, 1)] then
		return false,
			"symbol was provided in an infix operator place, but the symbol isn't a valid infix operator: " .. symbol
	end
	return true, true, symbol, a, b
end

---@return boolean
---@return boolean
local function shunting_yard_nil_handler(_)
	return true, false
end

---@class (exact) TaggedOperator
---@field type OperatorType
---@field symbol string

---@param yard { n: integer, [integer]: TaggedOperator }
---@param output { n: integer, [integer]: ConstructedSyntax }
local function shunting_yard_pop(yard, output)
	local yard_height = yard.n
	local output_length = output.n
	local operator = yard[yard_height]
	local operator_type = operator.type
	local operator_symbol = operator.symbol
	if operator_type == OperatorType.Prefix then
		local arg = output[output_length]
		local tree = metalanguage.list(nil, metalanguage.symbol(nil, operator_symbol), arg)
		yard[yard_height] = nil
		yard.n = yard_height - 1
		output[output_length] = tree
	elseif operator_type == OperatorType.Infix then
		local right = output[output_length]
		local left = output[output_length - 1]
		local tree = metalanguage.list(nil, left, metalanguage.symbol(nil, operator_symbol), right)
		yard[yard_height] = nil
		yard.n = yard_height - 1
		output[output_length] = nil
		output[output_length - 1] = tree
		output.n = output_length - 1
	else
		error("unknown operator type")
	end
end

---@param new_symbol string
---@param yard_operator TaggedOperator
local function shunting_yard_should_pop(new_symbol, yard_operator)
	-- new_symbol is always infix, as we never pop while adding a prefix operator
	-- prefix operators always have higher precedence than infix operators
	local yard_type = yard_operator.type
	if yard_type == OperatorType.Prefix then
		return true
	end
	if yard_type ~= OperatorType.Infix then
		error("unknown operator type")
	end
	local yard_symbol = yard_operator.symbol
	local new_data = infix_data[new_symbol:sub(1, 1)]
	local yard_data = infix_data[yard_symbol:sub(1, 1)]
	local new_precedence = new_data.precedence
	local yard_precedence = yard_data.precedence
	if new_precedence < yard_precedence then
		return true
	end
	if new_precedence > yard_precedence then
		return false
	end
	local new_associativity = new_data.associativity
	local yard_associativity = yard_data.associativity
	if new_associativity ~= yard_associativity then
		-- if you actually hit this error, it's because the infix_data is badly specified
		-- one of the precedence levels has both left- and right-associative operators
		-- please separate these operators into different precedence levels to disambiguate
		error("clashing associativities!!!")
	end
	if new_associativity == Associativity.l then
		return true
	end
	if new_associativity == Associativity.r then
		return false
	end
	error("unknown associativity")
end

---@param a ConstructedSyntax
---@param b ConstructedSyntax
---@param yard { n: integer, [integer]: TaggedOperator }
---@param output { n: integer, [integer]: ConstructedSyntax }
---@return boolean
---@return ConstructedSyntax|string
local function shunting_yard(a, b, yard, output)
	-- first, collect all prefix operators
	local is_prefix, prefix_symbol =
		a:match({ metalanguage.issymbol(shunting_yard_prefix_handler) }, metalanguage.failure_handler, nil)
	if is_prefix then
		local ok, next_a, next_b =
			b:match({ metalanguage.ispair(metalanguage.accept_handler) }, metalanguage.failure_handler, nil)
		if not ok then
			return ok, next_a
		end
		-- prefix operators always have higher precedence than infix operators,
		-- all have the same precedence as each other (conceptually), and are always right-associative
		-- this means we never need to pop the yard before adding a prefix operator to it
		yard.n = yard.n + 1
		yard[yard.n] = {
			type = OperatorType.Prefix,
			symbol = prefix_symbol,
		}
		return shunting_yard(next_a, next_b, yard, output)
	end
	-- no more prefix operators, now handle infix
	output.n = output.n + 1
	output[output.n] = a
	local ok, more, infix_symbol, next_a, next_b = b:match({
		metalanguage.listtail(
			shunting_yard_infix_handler,
			metalanguage.issymbol(metalanguage.accept_handler),
			metalanguage.any(metalanguage.accept_handler)
		),
		metalanguage.isnil(shunting_yard_nil_handler),
	}, metalanguage.failure_handler, nil)
	if not ok then
		return ok, more
	end
	if not more then
		while yard.n > 0 do
			shunting_yard_pop(yard, output)
		end
		return true, output[1]
	end
	while yard.n > 0 and shunting_yard_should_pop(infix_symbol, yard[yard.n]) do
		shunting_yard_pop(yard, output)
	end
	yard.n = yard.n + 1
	yard[yard.n] = {
		type = OperatorType.Infix,
		symbol = infix_symbol,
	}
	return shunting_yard(next_a, next_b, yard, output)
end

---@param symbol string
---@param arg ConstructedSyntax
---@return boolean
---@return OperatorType|string
---@return string?
---@return ConstructedSyntax?
local function expression_prefix_handler(_, symbol, arg)
	if not prefix_data[symbol:sub(1, 1)] then
		return false,
			"symbol was provided in a prefix operator place, but the symbol isn't a valid prefix operator: " .. symbol
	end
	return true, OperatorType.Prefix, symbol, arg
end

---@param left ConstructedSyntax
---@param symbol string
---@param right ConstructedSyntax
---@return boolean
---@return OperatorType|string
---@return string?
---@return ConstructedSyntax?
---@return ConstructedSyntax?
local function expression_infix_handler(_, left, symbol, right)
	if not infix_data[symbol:sub(1, 1)] then
		return false,
			"symbol was provided in an infix operator place, but the symbol isn't a valid infix operator: " .. symbol
	end
	return true, OperatorType.Infix, symbol, left, right
end

---@param args ExpressionArgs
---@param a ConstructedSyntax
---@param b ConstructedSyntax
---@return boolean
---@return inferrable | checkable | string
---@return Environment?
local function expression_pairhandler(args, a, b)
	local goal, env = args:unwrap()
	local orig_env = env
	local is_operator = false
	local operator_type
	local left, operator, right
	local sargs

	-- if the expression is a list containing prefix and infix expressions,
	-- parse it into a tree of simple prefix/infix expressions with shunting yard
	local ok, syntax = shunting_yard(a, b, { n = 0 }, { n = 0 })
	if ok then
		---@cast syntax ConstructedSyntax
		is_operator, operator_type, operator, left, right = syntax:match({
			metalanguage.listmatch(
				expression_prefix_handler,
				metalanguage.issymbol(metalanguage.accept_handler),
				metalanguage.any(metalanguage.accept_handler)
			),
			metalanguage.listmatch(
				expression_infix_handler,
				metalanguage.any(metalanguage.accept_handler),
				metalanguage.issymbol(metalanguage.accept_handler),
				metalanguage.any(metalanguage.accept_handler)
			),
		}, metalanguage.failure_handler, nil)
	end

	local combiner
	if is_operator and operator_type == OperatorType.Prefix then
		ok, combiner = env:get(operator .. "_")
		if not ok then
			return false, combiner
		end
		sargs = metalanguage.list(nil, left)
	elseif is_operator and operator_type == OperatorType.Infix then
		ok, combiner = env:get("_" .. operator .. "_")
		if not ok then
			return false, combiner
		end
		sargs = metalanguage.list(nil, left, right)
	else
		ok, combiner, env = a:match(
			{ expression(metalanguage.accept_handler, ExpressionArgs.new(expression_goal.infer, env)) },
			metalanguage.failure_handler,
			nil
		)
		if not ok then
			return false, combiner
		end
		sargs = b
	end
	---@cast combiner inferrable

	-- resolve first of the pair as an expression
	-- typecheck it
	-- check type to see how it should be combined
	-- either
	--   resolve rest of the pair as collect tuple
	--   pass it into the operative's arguments

	-- combiner was an evaluated typed value, now it isn't
	local type_of_term, usage_count, term = infer(combiner, env.typechecking_context)
	if type_of_term:is_operative_type() then
		local handler, userdata_type = type_of_term:unwrap_operative_type()
		-- operative input: env, syntax tree, goal type (if checked)
		local tuple_args = value_array(value.prim(sargs), value.prim(env), value.prim(term), value.prim(goal))
		local operative_result_val = evaluator.apply_value(handler, terms.value.tuple_value(tuple_args))
		-- result should be able to be an inferred term, can fail
		-- NYI: operative_cons in evaluator must use Maybe type once it exists
		-- if not operative_result_val:is_enum_value() then
		-- 	p(operative_result_val.kind)
		-- 	print(operative_result_val:pretty_print())
		-- 	return false, "applying operative did not result in value term with kind enum_value, typechecker or lua operative mistake when applying " .. tostring(a.anchor) .. " to the args " .. tostring(b.anchor)
		-- end
		-- variants: ok, error
		--if operative_result_val.variant == "error" then
		--	return false, semantic_error.operative_apply_failed(operative_result_val.data, { a.anchor, b.anchor })
		--end

		-- temporary, while it isn't a Maybe
		local operative_result_elems = operative_result_val:unwrap_tuple_value()
		local data = operative_result_elems[1]:unwrap_prim()
		local env = operative_result_elems[2]:unwrap_prim()
		--if not env then
		--	print("operative_result_val.elements[2]", operative_result_val.elements[2]:pretty_print())
		--	error "operative_result_val missing env"
		--end

		if goal:is_check() then
			local checkable = data
			if inferrable_term.value_check(checkable) == true then
				checkable = checkable_term.inferrable(checkable)
			end

			local goal_type = goal:unwrap_check()
			local usage_counts, term = evaluator.check(checkable, env.typechecking_context, goal_type)
			return true, checkable_term.inferrable(inferrable_term.typed(goal_type, usage_counts, term)), env
		elseif goal:is_infer() then
			if inferrable_term.value_check(data) == true then
				local resulting_type, usage_counts, term = infer(data, env.typechecking_context)

				return true, inferrable_term.typed(resulting_type, usage_counts, term), env
			end
		else
			error("NYI goal " .. goal.kind .. " for operative in expression_pairhandler")
		end
	end

	if type_of_term:is_pi() then
		local param_type, param_info, result_type, result_info = type_of_term:unwrap_pi()

		while param_info:unwrap_param_info() == value.visibility(visibility.implicit) do
			local metavar = evaluator.typechecker_state:metavariable()
			local metavalue = metavar:as_value()
			local metaresult = evaluator.apply_value(result_type, metavalue)
			if not metaresult:is_pi() then
				error("Result of applying function to a metavariable wasn't a pi type! This is bad for some reason!")
			end

			-- local new_term = inferrable_term.application(inferrable_term.typed(type_of_term, usage_array(), term), checkable_term.inferrable(inferrable_term.typed(param_type, usage_array(), terms.typed_term.literal(metavar:as_value()))))
			term = typed_term.application(term, terms.typed_term.literal(metavar:as_value()))
			type_of_term = metaresult
			param_type, param_info, result_type, result_info = type_of_term:unwrap_pi()
		end

		-- multiple quantity of usages in tuple with usage in function arguments
		local ok, tuple, env = sargs:match({
			collect_tuple(metalanguage.accept_handler, ExpressionArgs.new(expression_goal.check(param_type), env)),
		}, metalanguage.failure_handler, nil)

		if not ok then
			return false, tuple, env
		end

		return true, inferrable_term.application(inferrable_term.typed(type_of_term, usage_count, term), tuple), env
	end

	if type_of_term:is_prim_function_type() then
		local param_type, result_type = type_of_term:unwrap_prim_function_type()
		--print("checking prim_function_type call args with goal: (value term follows)")
		--print(param_type)
		-- multiple quantity of usages in tuple with usage in function arguments
		local ok, tuple, env = sargs:match({
			collect_prim_tuple(metalanguage.accept_handler, ExpressionArgs.new(expression_goal.check(param_type), env)),
		}, metalanguage.failure_handler, nil)

		if not ok then
			return false,
				semantic_error.prim_function_argument_collect_failed(tuple, { a.anchor, b.anchor }, {
					prim_function_type = type_of_term,
					prim_function_value = term,
				}, orig_env),
				env
		end

		return true, inferrable_term.application(inferrable_term.typed(type_of_term, usage_count, term), tuple), env
	end

	print("!!! about to fail of invalid type")
	print(combiner:pretty_print(env.typechecking_context))
	print("infers to")
	print(type_of_term)
	print("in")
	env.typechecking_context:dump_names()
	return false, "unknown type for pairhandler " .. type_of_term.kind, env
end

---@param str string
---@return string
local function split_dot_accessors(str)
	return str:match("([^.]+)%.(.+)")
end

---@param args ExpressionArgs
---@param name string
---@return boolean
---@return inferrable | checkable | string
---@return Environment
local function expression_symbolhandler(args, name)
	local goal, env = args:unwrap()
	--print("looking up symbol", name)
	--p(env)
	--print(name, split_dot_accessors(name))
	local front, rest = split_dot_accessors(name)
	if not front then
		local ok, val = env:get(name)
		if not ok then
			---@cast val string
			return ok, val, env
		end
		---@cast val -string
		if goal:is_check() then
			return true, checkable_term.inferrable(val), env
		end
		return ok, val, env
	else
		local ok, part = env:get(front)
		if not ok then
			---@cast part string
			return false, part, env
		end
		---@cast part -string
		while front do
			name = rest
			front, rest = split_dot_accessors(name)
			part = inferrable_term.record_elim(
				part,
				name_array(front or name),
				inferrable_term.bound_variable(#env.typechecking_context + 1)
			)
		end
		if goal:is_check() then
			return true, checkable_term.inferrable(part), env
		end
		return ok, part, env
	end
end

---@param args ExpressionArgs
---@param val inferrable | checkable
---@return boolean
---@return inferrable | checkable
---@return Environment
local function expression_valuehandler(args, val)
	local goal, env = args:unwrap()

	--TODO: proper checkable cases for literal values, requires more checkable terms
	if goal:is_check() then
		local ok, inf_term, env = expression_valuehandler(ExpressionArgs.new(expression_goal.infer, env), val)
		if not ok then
			return false, inf_term, env
		end
		---@cast inf_term -checkable
		return true, checkable_term.inferrable(inf_term), env
	end

	if not goal:is_infer() then
		error("expression_valuehandler NYI for " .. goal.kind)
	end

	if val.type == "f64" then
		--p(val)
		return true,
			inferrable_term.typed(value.prim_number_type, usage_array(), typed_term.literal(value.prim(val.val))),
			env
	end
	if val.type == "string" then
		return true,
			inferrable_term.typed(value.prim_string_type, usage_array(), typed_term.literal(value.prim(val.val))),
			env
	end
	p("valuehandler error", val)
	error("unknown value type " .. val.type)
end

expression = metalanguage.reducer(function(syntax, args)
	-- print('trying to expression', syntax)
	return syntax:match({
		metalanguage.ispair(expression_pairhandler),
		metalanguage.issymbol(expression_symbolhandler),
		metalanguage.isvalue(expression_valuehandler),
	}, metalanguage.failure_handler, args)
end, "expressions")

-- local constexpr =
--   metalanguage.reducer(
--     function(syntax, environment)
--       local ok, val =
--         syntax:match({expressions(metalanguage.accept_handler, environment)}, metalanguage.failure_handler, nil)
--       if not ok then return false, val end
--       return val:asconstant()
--     enfoundendd
--   )

-- operate_behavior[types.primop_kind] = function(self, ops, env)
--   -- print("evaluating operative")
--   -- p(self)
--   -- p(ops)
--   -- p(env)
--   return self.val(ops, env)
-- end

---@class OperativeError
---@field cause any
---@field anchor Anchor
---@field operative_name string
local OperativeError = {}
local external_error_mt = {
	__tostring = function(self)
		local message = "Lua error occured inside primitive operative "
			.. self.operative_name
			.. " "
			.. (self.anchor and tostring(self.anchor) or " at unknown position")
			.. ":\n"
			.. tostring(self.cause)
		return message
	end,
	__index = OperativeError,
}

---@param cause any
---@param anchor Anchor
---@param operative_name any
---@return OperativeError
function OperativeError.new(cause, anchor, operative_name)
	return setmetatable({
		anchor = anchor,
		cause = cause,
		operative_name = operative_name,
	}, external_error_mt)
end

---@param fn lua_operative
---@param name string
---@return inferrable
local function primitive_operative(fn, name)
	local debuginfo = debug.getinfo(fn)
	local debugstring = (name or error("name not passed to primitive_operative"))
		.. " "
		.. debuginfo.short_src
		.. ":"
		.. debuginfo.linedefined
	local aborting_fn = function(syn, env, userdata, goal)
		if not env or not env.exit_block then
			error("env passed to primitive_operative " .. debugstring .. " isn't an env or is nil", env)
		end
		-- userdata isn't passed in as it's always empty for primitive operatives
		local ok, res, env = fn(syn, env, goal)
		if not ok then
			error(OperativeError.new(res, syn.anchor, debugstring))
		end
		if not env or not env.exit_block then
			print(
				"env returned from fn passed to alicorn-expressions.primitive_operative isn't an env or is nil",
				env,
				" in ",
				debuginfo.short_src,
				debuginfo.linedefined
			)
			error("invalid env from primitive_operative fn " .. debugstring)
		end
		return res, env
	end
	-- what we're going for:
	-- (s : syntax, e : environment, u : wrapped_typed_term(userdata), g : goal) -> (goal_to_term(g), environment)
	--   goal one of inferable, mechanism, checkable

	-- 1: wrap fn as a typed prim
	-- this way it can take a prim tuple and return a prim tuple
	local typed_prim_fn = typed_term.literal(value.prim(aborting_fn))
	-- 2: wrap it to convert a normal tuple argument to a prim tuple
	-- and a prim tuple result to a normal tuple
	-- this way it can take a normal tuple and return a normal tuple
	local nparams = 4
	local tuple_conv_elements = typed_array(typed_term.bound_variable(2), typed_term.bound_variable(3))
	local prim_tuple_conv_elements = typed_array()
	for i = 1, nparams do
		-- + 1 because variable 1 is the argument tuple
		-- all variables that follow are the destructured tuple
		local var = typed_term.bound_variable(i + 1)
		prim_tuple_conv_elements:append(var)
	end
	local tuple_conv = typed_term.tuple_cons(tuple_conv_elements)
	local prim_tuple_conv = typed_term.prim_tuple_cons(prim_tuple_conv_elements)
	local param_names = name_array("#syntax", "#env", "#userdata", "#goal")
	local tuple_to_prim_tuple =
		typed_term.tuple_elim(param_names, typed_term.bound_variable(1), nparams, prim_tuple_conv)
	local tuple_to_prim_tuple_fn = typed_term.application(typed_prim_fn, tuple_to_prim_tuple)
	local result_names = name_array("#term", "#env")
	local tuple_to_tuple_fn = typed_term.tuple_elim(result_names, tuple_to_prim_tuple_fn, 2, tuple_conv)
	-- 3: wrap it in a closure with an empty capture, not a typed lambda
	-- this ensures variable 1 is the argument tuple
	local value_fn = value.closure("#OPERATIVE_PARAM", tuple_to_tuple_fn, runtime_context())

	local userdata_type = value.tuple_type(empty)
	return inferrable_term.typed(
		value.operative_type(value_fn, userdata_type),
		array(gen.builtin_number)(),
		typed_term.operative_cons(typed_term.tuple_cons(typed_array()))
	)
end

---@generic T
---@param args any
---@param a ConstructedSyntax
---@param b T
---@return boolean
---@return checkable|boolean
---@return checkable?
---@return T?
---@return Environment?
local function collect_tuple_pair_handler(args, a, b)
	local goal, env = args:unwrap()
	local ok, val
	ok, val, env = a:match(
		{ expression(metalanguage.accept_handler, ExpressionArgs.new(goal, env)) },
		metalanguage.failure_handler,
		nil
	)
	if ok and val and goal:is_check() and getmetatable(val) ~= checkable_term then
		val = checkable_term.inferrable(val)
	end
	if not ok then
		return false, val
	end
	return true, true, val, b, env
end

---@param args any
---@return boolean
---@return string
---@return nil
---@return nil
---@return Environment
local function collect_tuple_pair_too_many_handler(args)
	local goal, env = args:unwrap()
	return false, "tuple has too many elements for checked collect_tuple", nil, nil, env
end

---@param args any
---@return boolean
---@return boolean
---@return nil
---@return nil
---@return Environment
local function collect_tuple_nil_handler(args)
	local goal, env = args:unwrap()
	return true, false, nil, nil, env
end

---@param args any
---@return boolean
---@return string
---@return nil
---@return nil
---@return Environment
local function collect_tuple_nil_too_few_handler(args)
	local goal, env = args:unwrap()
	return false, "tuple has too few elements for checked collect_tuple", nil, nil, env
end

collect_tuple = metalanguage.reducer(
	---@param syntax ConstructedSyntax
	---@param args any
	---@return boolean
	---@return boolean|string|inferrable|checkable
	---@return Environment
	function(syntax, args)
		local goal, env = args:unwrap()
		local goal_type, closures, collected_terms

		if goal:is_check() then
			collected_terms = array(checkable_term)()
			goal_type = goal:unwrap_check()
			closures = evaluator.extract_tuple_elem_type_closures(goal_type:unwrap_tuple_type(), value_array())
		else
			collected_terms = inferrable_array()
		end

		local tuple_type_elems = value_array()
		local tuple_symbolic_elems = value_array()
		local ok, continue, next_term = true, true, nil
		local i = 0
		while ok and continue do
			i = i + 1
			-- checked version knows how many elems should be in the tuple
			if goal_type then
				if i > #closures then
					ok, continue, next_term, syntax, env = syntax:match({
						metalanguage.ispair(collect_tuple_pair_too_many_handler),
						metalanguage.isnil(collect_tuple_nil_handler),
					}, metalanguage.failure_handler, ExpressionArgs.new(goal, env))
				else
					local next_elem_type = evaluator.apply_value(closures[i], value.tuple_value(tuple_symbolic_elems))
					-- if next_elem_type:is_neutral() then
					-- 	print("collect_tuple: neutral goal type")
					-- 	print("from application of: (value term follows)")
					-- 	print(closures[i]:pretty_print())
					-- 	print("applied to: (value term follows)")
					-- 	print(value.tuple_value(tuple_symbolic_elems))
					-- 	error "neutral goal type"
					-- end

					ok, continue, next_term, syntax, env = syntax:match({
						metalanguage.ispair(collect_tuple_pair_handler),
						metalanguage.isnil(collect_tuple_nil_too_few_handler),
					}, metalanguage.failure_handler, ExpressionArgs.new(expression_goal.check(next_elem_type), env))
					if ok and continue then
						collected_terms:append(next_term)
						--print("goal type for next element in tuple: (value term follows)")
						--print(next_elem_type)
						--print("term we are checking: (checkable term follows)")
						--print(next_term:pretty_print(env.typechecking_context))
						local usages, typed_elem_term =
							evaluator.check(next_term, env.typechecking_context, next_elem_type)
						local elem_value = evaluator.evaluate(typed_elem_term, env.typechecking_context.runtime_context)
						tuple_symbolic_elems:append(elem_value)
					end
				end
				if not ok and type(continue) == "string" then
					continue = continue
						.. " (should have "
						.. tostring(#closures)
						.. ", found "
						.. tostring(#collected_terms)
						.. " so far)"
				end
			-- else we don't know how many elems so nil or pair are both valid
			else
				ok, continue, next_term, syntax, env = syntax:match({
					metalanguage.ispair(collect_tuple_pair_handler),
					metalanguage.isnil(collect_tuple_nil_handler),
				}, metalanguage.failure_handler, ExpressionArgs.new(goal, env))
				if ok and continue then
					collected_terms:append(next_term)
				end
			end
		end
		if not ok then
			return false, continue
		end

		if goal:is_infer() then
			return true, inferrable_term.tuple_cons(collected_terms), env
		elseif goal:is_check() then
			return true, checkable_term.tuple_cons(collected_terms), env
		else
			error("NYI: collect_tuple goal case " .. goal.kind)
		end
	end,
	"collect_tuple"
)

collect_prim_tuple = metalanguage.reducer(
	---@param syntax ConstructedSyntax
	---@param args any
	---@return boolean
	---@return boolean|string|inferrable|checkable
	---@return unknown
	function(syntax, args)
		local goal, env = args:unwrap()
		local goal_type, closures, collected_terms

		if goal:is_check() then
			collected_terms = array(checkable_term)()
			goal_type = goal:unwrap_check()
			closures = evaluator.extract_tuple_elem_type_closures(goal_type:unwrap_prim_tuple_type(), value_array())
		else
			collected_terms = inferrable_array
		end

		local type_elems = value_array()
		local tuple_symbolic_elems = value_array()
		local ok, continue, next_term = true, true, nil
		local i = 0
		while ok and continue do
			i = i + 1
			-- checked version knows how many elems should be in the tuple
			if goal_type then
				if i > #closures then
					ok, continue, next_term, syntax, env = syntax:match({
						metalanguage.ispair(collect_tuple_pair_too_many_handler),
						metalanguage.isnil(collect_tuple_nil_handler),
					}, metalanguage.failure_handler, ExpressionArgs.new(goal, env))
				else
					local next_elem_type = evaluator.apply_value(closures[i], value.tuple_value(tuple_symbolic_elems))
					type_elems:append(next_elem_type)

					ok, continue, next_term, syntax, env = syntax:match({
						metalanguage.ispair(collect_tuple_pair_handler),
						metalanguage.isnil(collect_tuple_nil_too_few_handler),
					}, metalanguage.failure_handler, ExpressionArgs.new(expression_goal.check(next_elem_type), env))
					if ok and continue then
						collected_terms:append(next_term)
						--print("trying to check tuple element as: (value term follows)")
						--print(next_elem_type)
						local usages, typed_elem_term =
							evaluator.check(next_term, env.typechecking_context, next_elem_type)
						local elem_value = evaluator.evaluate(typed_elem_term, env.typechecking_context.runtime_context)
						tuple_symbolic_elems:append(elem_value)
					end
				end
				if not ok and type(continue) == "string" then
					continue = continue
						.. " (should have "
						.. tostring(#closures)
						.. ", found "
						.. tostring(#collected_terms)
						.. " so far)"
				end
			-- else we don't know how many elems so nil or pair are both valid
			else
				ok, continue, next_term, syntax, env = syntax:match({
					metalanguage.ispair(collect_tuple_pair_handler),
					metalanguage.isnil(collect_tuple_nil_handler),
				}, metalanguage.failure_handler, ExpressionArgs.new(goal, env))
				if ok and continue then
					collected_terms:append(next_term)
				end
			end
		end
		if not ok then
			return false, continue
		end

		if goal:is_infer() then
			return true, inferrable_term.prim_tuple_cons(collected_terms), env
		elseif goal:is_check() then
			return true, checkable_term.prim_tuple_cons(collected_terms), env
		else
			error("NYI: collect_prim_tuple goal case " .. goal.kind)
		end
	end,
	"collect_prim_tuple"
)

local expressions_args = metalanguage.reducer(
	---@param syntax ConstructedSyntax
	---@param args any
	---@return boolean
	---@return boolean|table|string
	---@return Environment
	function(syntax, args)
		local goal, env = args:unwrap()
		local vals = {}
		local ok, continue = true, true
		while ok and continue do
			ok, continue, vals[#vals + 1], syntax, env = syntax:match({
				metalanguage.ispair(collect_tuple_pair_handler),
				metalanguage.isnil(collect_tuple_nil_handler),
			}, metalanguage.failure_handler, ExpressionArgs.new(goal, env))
		end
		if not ok then
			return false, continue
		end
		return true, vals, env
	end,
	"expressions_args"
)

local block = metalanguage.reducer(function(syntax, args)
	local goal, env = args:unwrap()
	assert(goal:is_infer(), "NYI non-infer cases for block")
	local lastval, newval
	local ok, continue = true, true
	while ok and continue do
		ok, continue, newval, syntax, env = syntax:match({
			metalanguage.ispair(collect_tuple_pair_handler),
			metalanguage.isnil(collect_tuple_nil_handler),
		}, metalanguage.failure_handler, ExpressionArgs.new(goal, env))
		if ok and continue then
			lastval = newval
		end
	end
	if not ok then
		return false, continue
	end
	return true, lastval, env
end, "block")

-- example usage of primitive_applicative
-- add(a, b) = a + b ->
-- local prim_num = terms.value.prim_number_type
-- primitive_applicative(function(a, b) return a + b end, {prim_num, prim_num}, {prim_num}),

---@param elems value[]
---@return value
local function build_prim_type_tuple(elems)
	local result = empty

	for i, v in ipairs(elems) do
		result = cons(result, const_combinator(v))
	end

	return terms.value.prim_tuple_type(result)
end

---@param fn function
---@param params value[]
---@param results value[]
---@return inferrable
local function primitive_applicative(fn, params, results)
	local literal_prim_fn = terms.typed_term.literal(terms.value.prim(fn))
	local prim_fn_type = terms.value.prim_function_type(build_prim_type_tuple(params), build_prim_type_tuple(results))

	return terms.inferrable_term.typed(prim_fn_type, usage_array(), literal_prim_fn)
end

---@param syntax ConstructedSyntax
---@param environment Environment
---@return ...
local function eval(syntax, environment)
	return syntax:match(
		{ expression(metalanguage.accept_handler, ExpressionArgs.new(expression_goal.infer, environment)) },
		metalanguage.failure_handler,
		nil
	)
end

---@param syntax ConstructedSyntax
---@param environment Environment
---@return ...
local function eval_block(syntax, environment)
	return syntax:match(
		{ block(metalanguage.accept_handler, ExpressionArgs.new(expression_goal.infer, environment)) },
		metalanguage.failure_handler,
		nil
	)
end

---Convenience wrapper inferred_expression(handler, env) -> expression(handler, expression_args(expression_goal.infer, env))
---@generic T
---@param handler fun(u: T, ...):...
---@param env Environment
---@return any
local function inferred_expression(handler, env)
	assert(handler, "no handler")
	assert(env and env.get, "no env")
	return expression(handler, ExpressionArgs.new(expression_goal.infer, env))
end

local alicorn_expressions = {
	expression = expression,
	inferred_expression = inferred_expression,
	-- constexpr = constexpr
	block = block,
	ExpressionArgs = ExpressionArgs,
	primitive_operative = primitive_operative,
	primitive_applicative = primitive_applicative,
	--define_operate = define_operate,
	collect_tuple = collect_tuple,
	expressions_args = expressions_args,
	eval = eval,
	eval_block = eval_block,
}
local internals_interface = require "./internals-interface"
internals_interface.alicorn_expressions = alicorn_expressions
return alicorn_expressions
