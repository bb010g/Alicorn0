-- SPDX-License-Identifier: Apache-2.0
-- SPDX-FileCopyrightText: 2025 Fundament Software SPC <https://fundament.software>
local internals_interface = require "internals-interface"

---@class (exact) glsl-print.glsl_registry.entry
---@field print (fun(pp: PrettyPrint, context: AnyContext, ...: typed))
---@field check (fun(self: typed, context: AnyContext): (is_printable: boolean))

---@type table<any, glsl-print.glsl_registry.entry>
internals_interface.glsl_registry = {}

local U = require "alicorn-utils"
local traits = require "traits"
-- stylua: ignore
---@module "terms-generators"
---@diagnostic disable-next-line: unused-local
do local terms_generators end

---@alias glsl-print.glsl_print_deriver.print (fun(self: typed, pp: PrettyPrint, context: AnyContext))
---@alias glsl-print.glsl_print_deriver.check (fun(self: typed, context: AnyContext): (is_printable: boolean))

---@param unknown typed
---@param pp PrettyPrint
---@param context AnyContext
local function glsl_print_fallback(
	unknown,
	pp,
	---@diagnostic disable-next-line: unused-local
	context
)
	pp:unit("/* wtf is this: ")
	pp:unit(tostring(unknown))
	pp:unit("*/")
end

---@param unknown typed
---@param context AnyContext
---@return boolean is_printable
local function glsl_check_fallback(
	---@diagnostic disable-next-line: unused-local
	unknown,
	---@diagnostic disable-next-line: unused-local
	context
)
	return false
end

---@type Deriver
local glsl_print_deriver = {
	record = function(_t, _info, _glsl_variants)
		error("notimp")
	end,
	enum = function(t, info, glsl_variants)
		local name = info.name
		local name_dot = name .. "."
		local variants = info.variants

		---@type table<string, glsl-print.glsl_print_deriver.print>
		local variant_glsl_printers = {}
		---@type table<string, glsl-print.glsl_print_deriver.check>
		local variant_glsl_checkers = {}
		for _, vname in ipairs(variants) do
			local vkind = name_dot .. vname
			local glsl_variant = glsl_variants[vname]
			if glsl_variant then
				variant_glsl_printers[vkind] = glsl_variant.print
				variant_glsl_checkers[vkind] = glsl_variant.check
			else
				variant_glsl_printers[vkind] = glsl_print_fallback
				variant_glsl_checkers[vkind] = glsl_check_fallback
			end
		end

		---@type glsl-print.glsl_print_deriver.print
		local function glsl_print(self, pp, context)
			return variant_glsl_printers[self.kind](self, pp, context)
		end

		---@type glsl-print.glsl_print_deriver.check
		local function glsl_check(self, context)
			return variant_glsl_checkers[self.kind](self, context)
		end

		traits.glsl_print:implement_on(t, { glsl_print = glsl_print, glsl_check = glsl_check })
	end,
}

---@class (exact) glsl-print.typed_term_override_glsl_print
---@field print glsl-print.glsl_print_deriver.print
---@field check glsl-print.glsl_print_deriver.check

---@type (table<string, glsl-print.typed_term_override_glsl_print>)
local typed_term_override_glsl_print = {}

typed_term_override_glsl_print.literal = {
	print = function(self, pp, context)
		local literal_value = self:unwrap_literal()

		if not literal_value:is_host_value() then
			return glsl_print_fallback(self, pp, context)
		end
		local val = literal_value:unwrap_host_value()
		pp:any(val, context)
	end,
	check = function(self, _check)
		local literal_value = self:unwrap_literal()
		if not literal_value:is_host_value() then
			return false
		end
		return true
	end,
}

---@param self typed
---@param subject typed
---@param index integer
---@param pp PrettyPrint
---@param context AnyContext
local function glsl_print_application(self, subject, index, pp, context)
	if index ~= 1 then
		glsl_print_fallback(self, pp, context)
		return
	end

	local f, arg = subject:unwrap_application()

	if not f:is_literal() or not f:unwrap_literal():is_host_value() then
		glsl_print_fallback(self, pp, context)
		return
	end
	local host_f = f:unwrap_literal():unwrap_host_value()

	local glsl_registry_entry = internals_interface.glsl_registry[host_f]
	if not glsl_registry_entry then
		glsl_print_fallback(self, pp, context)
		return
	end
	local glsl_print_fun = glsl_registry_entry.print

	local is_host_tuple_cons, elements = arg:as_host_tuple_cons()
	if not is_host_tuple_cons then
		glsl_print_fallback(self, pp, context)
		return
	end

	pp:_enter()
	glsl_print_fun(pp, context, elements:unpack())
	pp:_exit()
end

---@param self typed
---@param subject typed
---@param param_index integer
---@param pp PrettyPrint
---@param context AnyContext
local function glsl_print_variable(self, subject, param_index, pp, context)
	local var_index, _var_debug = subject:unwrap_bound_variable()

	local param_name_tuple, _param_debug = context:get(var_index)
	if not param_name_tuple then
		error(("variable with index %d not in context %s"):format(var_index, tostring(context)))
		-- glsl_print_fallback(self, pp, context)
		-- return
	end

	local param_names = param_name_tuple:unwrap_tuple_value()
	local param_name_value = param_names[param_index]
	local param_name = param_name_value:unwrap_name()

	pp:unit(param_name)
end

---@param self typed
---@param subject typed
---@param index integer
---@param context AnyContext
---@return boolean is_printable
local function glsl_check_application(self, subject, index, context)
	if index ~= 1 then
		return false
	end

	local f, arg = subject:unwrap_application()

	if not f:is_literal() or not f:unwrap_literal():is_host_value() then
		return false
	end
	local host_f = f:unwrap_literal():unwrap_host_value()

	local glsl_registry_entry = internals_interface.glsl_registry[host_f]
	if not glsl_registry_entry then
		return U.notail(glsl_check_fallback(self, context))
	end
	local glsl_check_fun = glsl_registry_entry.check

	local is_host_tuple_cons, _elements = arg:as_host_tuple_cons()
	if not is_host_tuple_cons then
		return U.notail(glsl_check_fallback(self, context))
	end

	return U.notail(glsl_check_fun(self, context))
end

---@param self typed
---@param subject typed
---@param param_index integer
---@param context AnyContext
---@return boolean is_printable
local function glsl_check_variable(self, subject, param_index, context)
	local var_index, _var_debug = subject:unwrap_bound_variable()

	local param_name_tuple, _param_debug = context:get(var_index)
	if not param_name_tuple then
		error(("variable with index %d not in context %s"):format(var_index, tostring(context)))
		-- return U.notail(glsl_check_fallback(self, pp, context))
	end

	local param_names = param_name_tuple:unwrap_tuple_value()
	local param_name_value = param_names[param_index]
	local _param_name = param_name_value:unwrap_name()

	return true
end

typed_term_override_glsl_print.tuple_element_access = {
	print = function(self, pp, context)
		local subject, index = self:unwrap_tuple_element_access()

		if subject:is_application() then
			return glsl_print_application(self, subject, index, pp, context)
		end
		if subject:is_bound_variable() then
			return glsl_print_variable(self, subject, index, pp, context)
		end
		return glsl_print_fallback(self, pp, context)
	end,
	check = function(self, context)
		local subject, index = self:unwrap_tuple_element_access()

		if subject:is_application() then
			return glsl_check_application(self, subject, index, context)
		end
		if subject:is_bound_variable() then
			return glsl_check_variable(self, subject, index, context)
		end
		return false
	end,
}

---@param pp PrettyPrint
---@param unknown typed
---@param context AnyContext
local function glsl_print(pp, unknown, context)
	local ty = type(unknown)
	if ty == "number" then
		pp:unit(string.format("%f", unknown))
		return
	end
	if ty == "table" then
		if pp.depth and pp.depth > 50 then
			pp:unit("DEPTH LIMIT EXCEEDED")
			return
		end
		local mt = getmetatable(unknown)
		local via_trait = mt and traits.glsl_print:get(mt)
		if via_trait then
			via_trait.glsl_print(unknown, context, pp)
			return
		end
		local glsl_registry_entry = mt and internals_interface.glsl_registry[mt]
		if glsl_registry_entry then
			local glsl_print_fun = glsl_registry_entry.print
			glsl_print_fun(pp, context, unknown)
			return
		end
	end
	glsl_print_fallback(unknown, pp, context)
end

return {
	glsl_print_deriver = glsl_print_deriver,
	glsl_print = glsl_print,
	typed_term_override_glsl_print = typed_term_override_glsl_print,
	glsl_print_trait = traits.glsl_print,
}
