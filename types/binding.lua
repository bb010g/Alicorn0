-- THIS FILE AUTOGENERATED BY terms-gen-meta.lua
---@meta "binding.lua"

---@class (exact) binding: EnumValue
binding = {}

---@return boolean
function binding:is_let() end
---@return string, inferrable
function binding:unwrap_let() end
---@return boolean, string, inferrable
function binding:as_let() end
---@return boolean
function binding:is_tuple_elim() end
---@return ArrayValue, inferrable
function binding:unwrap_tuple_elim() end
---@return boolean, ArrayValue, inferrable
function binding:as_tuple_elim() end
---@return boolean
function binding:is_annotated_lambda() end
---@return string, inferrable, Anchor, visibility
function binding:unwrap_annotated_lambda() end
---@return boolean, string, inferrable, Anchor, visibility
function binding:as_annotated_lambda() end
---@return boolean
function binding:is_program_sequence() end
---@return inferrable, Anchor
function binding:unwrap_program_sequence() end
---@return boolean, inferrable, Anchor
function binding:as_program_sequence() end

---@class (exact) bindingType: EnumType
---@field define_enum fun(self: bindingType, name: string, variants: Variants): bindingType
---@field let fun(name: string, expr: inferrable): binding
---@field tuple_elim fun(names: ArrayValue, subject: inferrable): binding
---@field annotated_lambda fun(param_name: string, param_annotation: inferrable, anchor: Anchor, visible: visibility): binding
---@field program_sequence fun(first: inferrable, anchor: Anchor): binding
return {}
