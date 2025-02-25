-- SPDX-License-Identifier: Apache-2.0
-- SPDX-FileCopyrightText: 2025 Fundament Software SPC <https://fundament.software>

local gen = require "terms-generators"
local traits = require "traits"

local function test_trait()
	local quantity = gen.declare_enum("quantity", {
		{ "erased" },
		{ "linear" },
		{ "unrestricted" },
	})
	local foo_trait = traits.declare_trait("foo")
	foo_trait:declare_method("fizzle")
	foo_trait:implement_on(quantity, {
		fizzle = function(self)
			return "i'm a quantity"
		end,
	})
	assert(foo_trait:get(quantity).fizzle(quantity.unrestricted) == "i'm a quantity")
end

test_trait()
